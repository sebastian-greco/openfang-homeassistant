#!/usr/bin/env bash
set -euo pipefail

OPTIONS_FILE="/data/options.json"

if [ ! -f "$OPTIONS_FILE" ]; then
  echo "[run.sh] ERROR: $OPTIONS_FILE not found — is the add-on config mapped correctly?"
  exit 1
fi

# --- umask: restrict file creation to owner-only before writing any config files ---
umask 077

TZNAME=$(jq -r '.timezone // "UTC"' "$OPTIONS_FILE")
BIND_LAN=$(jq -r '.bind_lan // false' "$OPTIONS_FILE")
LOG_LEVEL=$(jq -r '.log_level // "info"' "$OPTIONS_FILE")
TELEGRAM_TOKEN=$(jq -r '.telegram_bot_token // empty' "$OPTIONS_FILE")

# --- Timezone validation: reject path-traversal attempts (no '..' or leading '/') ---
if [[ "$TZNAME" == *".."* ]] || [[ "$TZNAME" == /* ]]; then
  echo "[run.sh] WARNING: Suspicious timezone value '$TZNAME', falling back to UTC"
  TZNAME="UTC"
fi

if [ -f "/usr/share/zoneinfo/$TZNAME" ]; then
  export TZ="$TZNAME"
  ln -snf "/usr/share/zoneinfo/$TZNAME" /etc/localtime 2>/dev/null || true
  echo "$TZNAME" > /etc/timezone 2>/dev/null || true
else
  echo "[run.sh] WARNING: Unknown timezone '$TZNAME', falling back to UTC"
  TZNAME="UTC"
  export TZ="UTC"
  ln -snf "/usr/share/zoneinfo/UTC" /etc/localtime 2>/dev/null || true
  echo "UTC" > /etc/timezone 2>/dev/null || true
fi

if [ "$BIND_LAN" = "true" ]; then
  BIND_ADDR="0.0.0.0"
else
  BIND_ADDR="127.0.0.1"
fi

# Internal port is always 4200; not a user option.
GATEWAY_PORT=4200

# Mark control variables readonly so user-supplied env vars cannot override them.
readonly BIND_ADDR GATEWAY_PORT

export HOME="/data"
export RUST_LOG="$LOG_LEVEL"
export OPENFANG_LISTEN="${BIND_ADDR}:${GATEWAY_PORT}"

if [ -n "$TELEGRAM_TOKEN" ]; then
  export TELEGRAM_BOT_TOKEN="$TELEGRAM_TOKEN"
fi

# --- Export user-supplied env vars, blocking reserved keys ---
# Use an associative array for the blocklist so it is immune to IFS manipulation.
declare -A RESERVED_MAP
for _k in HOME TZ PATH LD_PRELOAD LD_LIBRARY_PATH OPENFANG_LISTEN OPENFANG_HOME RUST_LOG TELEGRAM_BOT_TOKEN; do
  RESERVED_MAP["$_k"]=1
done

ENV_VARS_JSON=$(jq -c '.env_vars // []' "$OPTIONS_FILE")
if [ "$ENV_VARS_JSON" != "[]" ]; then
  while IFS= read -r -d '' key && IFS= read -r -d '' value; do
    if [ -z "$key" ]; then continue; fi
    if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "[run.sh] WARNING: Skipping env var with invalid name: $key"
      continue
    fi
    if [ "${RESERVED_MAP[$key]+set}" = "set" ]; then
      echo "[run.sh] WARNING: Skipping reserved env var: $key"
      continue
    fi
    # Guard against readonly/special bash variables that would abort under set -e.
    if ! (export "$key=$value") 2>/dev/null; then
      echo "[run.sh] WARNING: Cannot export env var '$key' (readonly or special) — skipping"
      continue
    fi
    export "$key=$value"
    if [[ "$key" =~ (KEY|TOKEN|SECRET|PASS|PASSWORD|CREDENTIAL) ]]; then
      echo "[run.sh] Exported env var: $key=(redacted)"
    else
      echo "[run.sh] Exported env var: $key"
    fi
  done < <(printf '%s' "$ENV_VARS_JSON" | jq -j '.[] | .name, "\u0000", (.value | tostring), "\u0000"')
fi

export OPENFANG_HOME="${HOME}/.openfang"
mkdir -p "$OPENFANG_HOME"

CONFIG_FILE="${OPENFANG_HOME}/config.toml"
echo "[run.sh] Writing config.toml to $CONFIG_FILE"
cat > "$CONFIG_FILE" <<TOML
api_listen = "${BIND_ADDR}:${GATEWAY_PORT}"
TOML

write_nginx_conf() {
  cat > /etc/nginx/nginx.conf <<NGINX
worker_processes 1;
error_log /dev/stderr warn;
pid /var/run/nginx.pid;

events { worker_connections 256; }

http {
  access_log off;

  map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
  }

  server {
    listen 8099;
    server_name _;

    location / {
      proxy_pass http://127.0.0.1:${GATEWAY_PORT};
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Ingress-Path \$http_x_ingress_path;
      proxy_redirect off;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
    }
  }
}
NGINX
}

write_nginx_conf

# Validate nginx config before starting
if ! nginx -t 2>&1; then
  echo "[run.sh] ERROR: nginx config validation failed — aborting"
  exit 1
fi

OPENFANG_PID=""
NGINX_PID=""
SHUTTING_DOWN="false"

shutdown_handler() {
  SHUTTING_DOWN="true"
  echo "[run.sh] Shutdown requested — stopping services..."

  if [ -n "$NGINX_PID" ] && kill -0 "$NGINX_PID" 2>/dev/null; then
    kill -TERM "$NGINX_PID" 2>/dev/null || true
    wait "$NGINX_PID" 2>/dev/null || true
  fi

  if [ -n "$OPENFANG_PID" ] && kill -0 "$OPENFANG_PID" 2>/dev/null; then
    kill -TERM "$OPENFANG_PID" 2>/dev/null || true
    wait "$OPENFANG_PID" 2>/dev/null || true
  fi
}

trap shutdown_handler INT TERM

echo "[run.sh] Starting nginx ingress proxy on :8099 -> 127.0.0.1:${GATEWAY_PORT}"
nginx -g 'daemon off;' &
NGINX_PID=$!

sleep 1
if ! kill -0 "$NGINX_PID" 2>/dev/null; then
  echo "[run.sh] ERROR: nginx failed to start"
  exit 1
fi

start_openfang() {
  echo "[run.sh] Starting openfang (listen: ${BIND_ADDR}:${GATEWAY_PORT}, log: ${LOG_LEVEL})"
  openfang start &
  OPENFANG_PID=$!
}

start_openfang

# Monitor both processes with wait -n -p so nginx death is detected immediately,
# even while openfang is still running. (-p requires bash 5.1+; bookworm ships 5.2)
while true; do
  EXITED_PID=0
  EXIT_CODE=0
  wait -n -p EXITED_PID || EXIT_CODE=$?
  if [ "$SHUTTING_DOWN" = "true" ]; then
    break
  fi

  if [ "$EXITED_PID" = "$NGINX_PID" ]; then
    echo "[run.sh] ERROR: nginx died unexpectedly (code ${EXIT_CODE}) — exiting container"
    kill -TERM "$OPENFANG_PID" 2>/dev/null || true
    wait "$OPENFANG_PID" 2>/dev/null || true
    exit 1
  fi

  if [ "$EXITED_PID" = "$OPENFANG_PID" ]; then
    echo "[run.sh] openfang exited (code ${EXIT_CODE}) — restarting in 3s..."
    sleep 3
    start_openfang
  fi
done

echo "[run.sh] Exited cleanly."
