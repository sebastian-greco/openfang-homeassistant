# OpenFang Add-on Documentation

## Overview

OpenFang is an open-source **Agent Operating System** built in Rust — a single ~32 MB binary that runs autonomous agents on your schedule, 24/7. It ships with a built-in WebChat UI and bridges to Telegram, Discord, and Slack.

This add-on runs OpenFang inside Home Assistant OS with persistent storage so your agents, memory, and configuration survive add-on updates.

---

## Installation

1. **Add this repository** to Home Assistant:
   - Go to **Settings → Add-ons → Add-on Store → ⋮ → Repositories**
   - Paste: `https://github.com/RightNow-AI/openfang-homeassistant`
   - Click **Add**

2. Find **OpenFang** in the store and click **Install**.

3. Configure the add-on options (see below), then click **Start**.

4. Click **Open Web UI** to access the OpenFang WebChat dashboard.

---

## Configuration Options

| Option | Type | Default | Description |
|---|---|---|---|
| `timezone` | string | `Europe/Rome` | Container timezone (e.g. `America/New_York`). |
| `gateway_port` | int | `4200` | Port OpenFang listens on. Also mapped externally. |
| `bind_lan` | bool | `false` | If `true`, bind to `0.0.0.0` instead of `127.0.0.1` (required if accessing the port externally without ingress). |
| `telegram_bot_token` | string | _(optional)_ | Your Telegram bot token. Passed as `TELEGRAM_BOT_TOKEN` to OpenFang. |
| `log_level` | string | `info` | Log verbosity: `trace`, `debug`, `info`, `warn`, `error`. |
| `env_vars` | list | `[]` | Arbitrary env vars forwarded to OpenFang at startup. |

### Example configuration

```yaml
timezone: "America/New_York"
gateway_port: 4200
bind_lan: false
telegram_bot_token: "123456:ABC-your-bot-token"
log_level: "info"
env_vars:
  - name: ANTHROPIC_API_KEY
    value: "sk-ant-..."
  - name: OPENAI_API_KEY
    value: "sk-..."
```

---

## Persistent Storage

All OpenFang data is stored in `/data/.openfang/` inside the add-on, which maps to the HA persistent add-on config directory. This includes:

- `config.toml` — OpenFang configuration
- `data/openfang.db` — SQLite memory database
- `agents/` — Your agent definitions
- `daemon.json` — Runtime state

Data **survives add-on updates and HA reboots**.

---

## LLM Provider Setup

OpenFang supports 27+ LLM providers. Set your API keys via `env_vars`:

```yaml
env_vars:
  - name: ANTHROPIC_API_KEY
    value: "sk-ant-api03-..."
```

Then configure the default model in the OpenFang WebChat UI (or edit `/data/.openfang/config.toml`):

```toml
[default_model]
provider = "anthropic"
model = "claude-sonnet-4-20250514"
api_key_env = "ANTHROPIC_API_KEY"
```

---

## Telegram Bridge Setup

1. Create a bot via [@BotFather](https://t.me/BotFather) — copy the token.
2. Set `telegram_bot_token` in the add-on config.
3. In the OpenFang WebChat UI, configure the Telegram channel adapter.

The `TELEGRAM_BOT_TOKEN` env var is automatically set from your add-on config.

---

## Migrating from OpenClaw

If you have an existing OpenClaw installation, OpenFang's built-in migration tool handles config conversion, agent import, and memory transfer:

```bash
openfang migrate --from openclaw --source-dir /addon_configs/openclaw_assistant/clawd
```

Run this from the HA terminal (SSH or terminal add-on) after installing OpenFang.

A `migration_report.md` is written to `/data/.openfang/` with a summary of what was imported.

---

## Accessing the WebChat UI

Two ways to access the UI:

1. **HA Ingress** (recommended): Click **Open Web UI** in the add-on page. No extra ports needed.
2. **Direct access**: If `bind_lan: true` is set, access via `http://<ha-ip>:4200` from your LAN.

---

## Architecture Notes

- The WebChat UI and REST API share the same port (4200) — they are part of the same OpenFang binary.
- The ingress proxy (nginx inside the container) listens on port 8099 and proxies to OpenFang on 127.0.0.1:4200. This is only used for the HA panel embed.
- WebSocket connections (for live chat) are proxied through with `Upgrade` headers preserved.

---

## Troubleshooting

**OpenFang crashes on startup**
- Check the add-on logs. Look for `config.toml` parse errors.
- Ensure at least one LLM API key is set via `env_vars`.

**UI shows "Connecting..." indefinitely**
- OpenFang may still be initializing. Wait ~10 seconds, then refresh.
- Check logs for port binding errors — another service may be using port 4200.

**Telegram bot not responding**
- Verify the bot token is correct.
- Ensure the `[telegram]` section is configured in `config.toml`.

**Port 4200 not accessible from LAN**
- Set `bind_lan: true` in the add-on config and restart.
- Ensure port 4200/tcp is mapped in the add-on Network settings.
