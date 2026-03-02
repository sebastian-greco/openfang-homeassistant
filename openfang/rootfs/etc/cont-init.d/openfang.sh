#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Initialise OpenFang: timezone, env vars, nginx config, data directory.
# ==============================================================================

OPTIONS_FILE="/data/options.json"

if [ ! -f "$OPTIONS_FILE" ]; then
  bashio::log.error "options.json not found at ${OPTIONS_FILE}"
  exit 1
fi

# --- Timezone ---
TZNAME=$(jq -r '.timezone // "UTC"' "$OPTIONS_FILE")
if [[ "$TZNAME" == *".."* ]] || [[ "$TZNAME" == /* ]]; then
  bashio::log.warning "Suspicious timezone '${TZNAME}', falling back to UTC"
  TZNAME="UTC"
fi
if [ -f "/usr/share/zoneinfo/$TZNAME" ]; then
  ln -snf "/usr/share/zoneinfo/$TZNAME" /etc/localtime 2>/dev/null || true
  echo "$TZNAME" > /etc/timezone 2>/dev/null || true
else
  bashio::log.warning "Unknown timezone '${TZNAME}', falling back to UTC"
  TZNAME="UTC"
  ln -snf "/usr/share/zoneinfo/UTC" /etc/localtime 2>/dev/null || true
  echo "UTC" > /etc/timezone 2>/dev/null || true
fi
printf '%s' "$TZNAME" > /var/run/s6/container_environment/TZ

# --- Core env vars (written to s6 container environment) ---
BIND_LAN=$(jq -r '.bind_lan // false' "$OPTIONS_FILE")
LOG_LEVEL=$(jq -r '.log_level // "info"' "$OPTIONS_FILE")
TELEGRAM_TOKEN=$(jq -r '.telegram_bot_token // empty' "$OPTIONS_FILE")

if [ "$BIND_LAN" = "true" ]; then
  BIND_ADDR="0.0.0.0"
else
  BIND_ADDR="127.0.0.1"
fi
GATEWAY_PORT=4200

printf '%s' "$BIND_ADDR"                     > /var/run/s6/container_environment/OPENFANG_LISTEN_ADDR
printf '%s:%s' "$BIND_ADDR" "$GATEWAY_PORT"  > /var/run/s6/container_environment/OPENFANG_LISTEN
printf '%s' "$LOG_LEVEL"                     > /var/run/s6/container_environment/RUST_LOG
printf '/data'                               > /var/run/s6/container_environment/HOME
printf '/data/.openfang'                     > /var/run/s6/container_environment/OPENFANG_HOME

if [ -n "$TELEGRAM_TOKEN" ]; then
  printf '%s' "$TELEGRAM_TOKEN" > /var/run/s6/container_environment/TELEGRAM_BOT_TOKEN
fi

# --- User-supplied env vars ---
declare -A RESERVED_MAP
for _k in HOME TZ PATH LD_PRELOAD LD_LIBRARY_PATH OPENFANG_LISTEN OPENFANG_HOME RUST_LOG TELEGRAM_BOT_TOKEN; do
  RESERVED_MAP["$_k"]=1
done

ENV_VARS_JSON=$(jq -c '.env_vars // []' "$OPTIONS_FILE")
if [ "$ENV_VARS_JSON" != "[]" ]; then
  while IFS= read -r -d '' key && IFS= read -r -d '' value; do
    if [ -z "$key" ]; then continue; fi
    if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      bashio::log.warning "Skipping env var with invalid name: ${key}"
      continue
    fi
    if [ "${RESERVED_MAP[$key]+set}" = "set" ]; then
      bashio::log.warning "Skipping reserved env var: ${key}"
      continue
    fi
    printf '%s' "$value" > "/var/run/s6/container_environment/${key}"
    if [[ "$key" =~ (KEY|TOKEN|SECRET|PASS|PASSWORD|CREDENTIAL) ]]; then
      bashio::log.info "Exported env var: ${key}=(redacted)"
    else
      bashio::log.info "Exported env var: ${key}"
    fi
  done < <(printf '%s' "$ENV_VARS_JSON" | jq -j '.[] | .name, "\u0000", (.value | tostring), "\u0000"')
fi

# --- Data directory ---
mkdir -p /data/.openfang

# --- Write config.toml ---
CONFIG_FILE="/data/.openfang/config.toml"
bashio::log.info "Writing config.toml to ${CONFIG_FILE}"
LLM_PROVIDER=$(jq -r '.llm_provider // "github-copilot"' "$OPTIONS_FILE")
LLM_MODEL=$(jq -r '.llm_model // "gpt-4o"' "$OPTIONS_FILE")

# Determine api_key_env from provider
case "$LLM_PROVIDER" in
  github-copilot|copilot) KEY_ENV="GITHUB_TOKEN" ;;
  anthropic)              KEY_ENV="ANTHROPIC_API_KEY" ;;
  openai)                 KEY_ENV="OPENAI_API_KEY" ;;
  gemini)                 KEY_ENV="GEMINI_API_KEY" ;;
  groq)                   KEY_ENV="GROQ_API_KEY" ;;
  deepseek)               KEY_ENV="DEEPSEEK_API_KEY" ;;
  openrouter)             KEY_ENV="OPENROUTER_API_KEY" ;;
  mistral)                KEY_ENV="MISTRAL_API_KEY" ;;
  together)               KEY_ENV="TOGETHER_API_KEY" ;;
  ollama|vllm|lmstudio)  KEY_ENV="" ;;
  *)                      KEY_ENV="" ;;
esac

if [ -n "$KEY_ENV" ]; then
  cat > "$CONFIG_FILE" <<TOML
api_listen = "${BIND_ADDR}:${GATEWAY_PORT}"

[default_model]
provider = "${LLM_PROVIDER}"
model = "${LLM_MODEL}"
api_key_env = "${KEY_ENV}"
TOML
else
  cat > "$CONFIG_FILE" <<TOML
api_listen = "${BIND_ADDR}:${GATEWAY_PORT}"

[default_model]
provider = "${LLM_PROVIDER}"
model = "${LLM_MODEL}"
TOML
fi

# --- Write nginx config ---
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

if ! nginx -t 2>&1; then
  bashio::log.error "nginx config validation failed"
  exit 1
fi

bashio::log.info "OpenFang initialisation complete"
