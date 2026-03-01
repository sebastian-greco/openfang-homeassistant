#!/usr/bin/env bash
set -euo pipefail

OPTIONS_FILE="/data/options.json"

if [ ! -f "$OPTIONS_FILE" ]; then
  echo "[run.sh] ERROR: $OPTIONS_FILE not found — is the add-on config mapped correctly?"
  exit 1
fi

TZNAME=$(jq -r '.timezone // "Europe/Rome"' "$OPTIONS_FILE")
GATEWAY_PORT=$(jq -r '.gateway_port // 4200' "$OPTIONS_FILE")
BIND_LAN=$(jq -r '.bind_lan // false' "$OPTIONS_FILE")
LOG_LEVEL=$(jq -r '.log_level // "info"' "$OPTIONS_FILE")
TELEGRAM_TOKEN=$(jq -r '.telegram_bot_token // empty' "$OPTIONS_FILE")

export TZ="$TZNAME"
ln -snf "/usr/share/zoneinfo/$TZNAME" /etc/localtime 2>/dev/null || true
echo "$TZNAME" > /etc/timezone 2>/dev/null || true

if [ "$BIND_LAN" = "true" ]; then
  BIND_ADDR="0.0.0.0"
else
  BIND_ADDR="127.0.0.1"
fi

export HOME="/data"
export RUST_LOG="$LOG_LEVEL"
export OPENFANG_LISTEN="${BIND_ADDR}:${GATEWAY_PORT}"

if [ -n "$TELEGRAM_TOKEN" ]; then
  export TELEGRAM_BOT_TOKEN="$TELEGRAM_TOKEN"
fi

ENV_VARS_JSON=$(jq -c '.env_vars // []' "$OPTIONS_FILE")
if [ "$ENV_VARS_JSON" != "[]" ]; then
  while IFS= read -r -d '' key && IFS= read -r -d '' value; do
    if [ -n "$key" ] && [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      export "$key=$value"
      echo "[run.sh] Exported env var: $key"
    fi
  done < <(printf '%s' "$ENV_VARS_JSON" | jq -j '.[] | .name, "\u0000", (.value | tostring), "\u0000"')
fi

OPENFANG_HOME="${HOME}/.openfang"
mkdir -p "$OPENFANG_HOME"

CONFIG_FILE="${OPENFANG_HOME}/config.toml"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[run.sh] Writing default config.toml to $CONFIG_FILE"
  cat > "$CONFIG_FILE" <<TOML
api_listen = "${BIND_ADDR}:${GATEWAY_PORT}"
TOML
fi

write_nginx_conf() {
  cat > /etc/nginx/nginx.conf <<NGINX
worker_processes 1;
error_log /dev/stderr warn;
pid /var/run/nginx.pid;

events { worker_connections 256; }

http {
  access_log off;

  server {
    listen 8099;
    server_name _;

    location / {
      proxy_pass http://127.0.0.1:${GATEWAY_PORT};
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
    }
  }
}
NGINX
}

write_nginx_conf

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

while true; do
  EXIT_CODE=0
  wait "$OPENFANG_PID" || EXIT_CODE=$?

  if [ "$SHUTTING_DOWN" = "true" ]; then
    break
  fi

  echo "[run.sh] openfang exited (code ${EXIT_CODE}) — restarting in 3s..."
  sleep 3
  start_openfang
done

echo "[run.sh] Exited cleanly."
