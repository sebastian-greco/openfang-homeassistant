# OpenFang Home Assistant Add-on

[![Release](https://img.shields.io/github/v/release/RightNow-AI/openfang-homeassistant?style=flat-square)](https://github.com/RightNow-AI/openfang-homeassistant/releases)
[![License](https://img.shields.io/github/license/RightNow-AI/openfang-homeassistant?style=flat-square)](LICENSE)

Run [OpenFang](https://github.com/RightNow-AI/openfang) — the open-source Agent OS — as a native Home Assistant add-on.

**One binary. Persistent storage. Embedded WebChat UI. Telegram/Discord/Slack bridges.**

---

## Add-ons in this repository

### OpenFang

![Supports amd64][amd64-badge]
![Supports aarch64][aarch64-badge]

OpenFang is an Agent Operating System built in Rust. A single ~32 MB binary gives you:

- Autonomous **Hands** (Researcher, Lead Gen, Collector, Predictor, Browser, Twitter, Clip)
- 27+ LLM providers (Anthropic, OpenAI, Gemini, Groq, Ollama, and more)
- Built-in **WebChat UI** at port 4200
- Telegram, Discord, and Slack channel bridges
- Workflow engine, memory substrate, MCP server support

All agent data, memory, and configuration are stored persistently and survive add-on updates.

---

## Installation

1. Click the button below **or** add the repository URL manually:

   [![Add repository to HA][repo-badge]][repo-url]

   **Manual**: Go to **Settings → Add-ons → Add-on Store → ⋮ → Repositories** and add:
   ```
   https://github.com/RightNow-AI/openfang-homeassistant
   ```

2. Find **OpenFang** in the add-on store and click **Install**.

3. Set your LLM API key in the add-on configuration:
   ```yaml
   env_vars:
     - name: ANTHROPIC_API_KEY
       value: "sk-ant-api03-..."
   ```

4. Click **Start**, then **Open Web UI** to access the OpenFang dashboard.

---

## Quick Start (step-by-step for testing)

### Prerequisites

- Home Assistant OS or Supervised installation
- A working LLM API key (Anthropic, OpenAI, Groq, etc.)

### Steps

1. **Add the repository** (see Installation above).

2. **Install the add-on** from the store.

3. **Configure** — in the add-on **Configuration** tab set at minimum:
   ```yaml
   env_vars:
     - name: ANTHROPIC_API_KEY
       value: "sk-ant-..."
   ```

4. **Start** the add-on.

5. **Watch logs** — you should see:
   ```
   [run.sh] Starting openfang (listen: 127.0.0.1:4200, log: info)
   [ok] Kernel booted
   [ok] API: http://127.0.0.1:4200
   ```

6. **Open Web UI** — click the button in the add-on page. The OpenFang WebChat loads embedded in HA.

7. **First run** — OpenFang will prompt you to complete setup (model selection) via the WebChat. Follow the on-screen wizard.

8. **Telegram** (optional):
   - Create a bot via [@BotFather](https://t.me/BotFather)
   - Add `telegram_bot_token: "your-token"` to the config
   - Restart the add-on
   - Configure the Telegram adapter in the WebChat UI

### Testing the add-on locally (Docker)

You can test the Dockerfile locally before pushing to HA:

```bash
# Build for your current arch
docker build \
  --build-arg BUILD_FROM=debian:bookworm-slim \
  --build-arg TARGETARCH=amd64 \
  -t openfang-addon-test \
  ./openfang

# Run with a fake options.json
mkdir -p /tmp/openfang-test
cat > /tmp/openfang-test/options.json <<'EOF'
{
  "timezone": "Europe/Rome",
  "gateway_port": 4200,
  "bind_lan": false,
  "log_level": "info",
  "env_vars": [
    {"name": "ANTHROPIC_API_KEY", "value": "sk-ant-..."}
  ]
}
EOF

docker run -it --rm \
  -p 4200:4200 \
  -v /tmp/openfang-test:/data \
  -e ANTHROPIC_API_KEY="sk-ant-..." \
  openfang-addon-test
```

Then open `http://localhost:4200` in your browser.

---

## Architecture

```
HA Ingress → nginx (:8099) → OpenFang (:4200)
                              ├── WebChat UI (/)
                              ├── REST API (/api/*)
                              └── WebSocket (/ws/*)
```

- **No complexity**: OpenFang is a single binary. No Node.js, no Homebrew, no npm, no Python runtime.
- **Persistent storage**: Everything in `/data/.openfang/` — survives container rebuilds.
- **Architectures**: amd64 and aarch64. armv7 is not supported (no upstream release asset).

---

## Migrating from OpenClaw

```bash
openfang migrate --from openclaw --source-dir /addon_configs/openclaw_assistant/clawd
```

Run this from an SSH session or the HA terminal add-on after installing OpenFang. A `migration_report.md` will be written to `/data/.openfang/` listing everything imported.

---

## Contributing

Issues and PRs welcome at [GitHub](https://github.com/RightNow-AI/openfang-homeassistant).

---

[amd64-badge]: https://img.shields.io/badge/amd64-yes-green?style=flat-square
[aarch64-badge]: https://img.shields.io/badge/aarch64-yes-green?style=flat-square
[repo-badge]: https://img.shields.io/badge/Add%20to%20Home%20Assistant-41BDF5?style=flat-square&logo=home-assistant&logoColor=white
[repo-url]: https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FRightNow-AI%2Fopenfang-homeassistant
