# Installing the local LLM stack

The installer supports Ubuntu/Xubuntu 22.04 and 24.04 with systemd.
Run it as your normal user. It uses sudo for package and service changes.
Internet access and sufficient storage for Python dependencies and models are
required. Model performance depends on available RAM and GPU hardware.

The default `--python auto` uses a compatible system Python when one is present.
On Ubuntu 22.04, whose system Python is 3.10, the installer downloads a managed
Python 3.11 through `uv` into the Open WebUI installation. It does not replace
Ubuntu's system Python. Ubuntu 24.04 users can use the distribution packages:

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv
./scripts/install-local-llm.sh
```

To use an independently installed Python 3.11 or 3.12 with venv support:

```bash
./scripts/install-local-llm.sh --python python3.11
```

The script validates prerequisites, installs curl and CA certificates, installs
Ollama if missing, and enables its system service. An existing Ollama installation
must provide an `ollama.service` listening on localhost port 11434.
It installs Open WebUI into `$HOME/open-webui/venv`, stores application data in
`$HOME/open-webui/data`, and runs the service from `$HOME/open-webui` so its secret
key persists there. It writes `/etc/systemd/system/open-webui.service` and restarts
that service. This unit name is owned by this installer; rerunning replaces it.

Open http://localhost:8080 and create your administrator account. By default,
only this computer can connect. After account setup, network access can be enabled:

```bash
./scripts/install-local-llm.sh --host 0.0.0.0
```

This exposes HTTP on all IPv4 interfaces reachable through your firewall. Use
appropriate access controls and HTTPS when deploying beyond a trusted local host.

Configure the installer with switches. Switches override environment variables,
which override the built-in defaults:

| Switch / environment variable | Default | Purpose |
| --- | --- | --- |
| `--embedding-model` / `EMBEDDING_MODEL` | `nomic-embed-text` | Local Ollama embedding model for RAG |
| `--model` / `MODEL` | `qwen3:1.7b` | Model downloaded through Ollama |
| `--install-dir` / `OPENWEBUI_DIR` | `$HOME/open-webui` | Absolute installation directory |
| `--python` / `PYTHON_BIN` | `auto` | Use system Python 3.11/3.12 or provision Python 3.11 with `uv` |
| `--host` / `WEBUI_HOST` | `127.0.0.1` | Local binding, or `0.0.0.0` for network access |
| `--port` / `WEBUI_PORT` | `8080` | HTTP port |

Installation paths may contain letters, digits, underscores, dots, slashes and
hyphens. Repeat any custom settings on subsequent runs. Existing virtual
environments and data are reused; rerunning does not request package upgrades.
Use a new installation directory if an existing venv uses unsupported Python.
An interrupted run may leave packages or services installed; correct the reported
problem and rerun. There is no automatic rollback.

The installer waits for Ollama and WebUI HTTP readiness and exits nonzero on
failure. On timeout, it prints recent service logs. It does not perform a model
inference test. For troubleshooting:

```bash
sudo journalctl -u ollama -u open-webui -n 100 --no-pager
./scripts/install-local-llm.sh --help
```

## Local document retrieval

The installer downloads the embedding model before starting WebUI and configures
Ollama as the RAG embedding provider at `http://127.0.0.1:11434`. These are initial
defaults; existing database settings can take precedence. Verify the provider and
model in Admin Settings > Documents on existing installations. Changing the
embedding model requires reindexing existing knowledge documents. See the
[README walkthrough](../README.md#ask-questions-about-your-documents-rag).

## Preview configuration

```bash
./scripts/install-local-llm.sh --show-config
./scripts/install-local-llm.sh --model gemma4:12b --port 8081 --show-config
```

`--show-config` validates option values and prints effective settings without
checking host prerequisites or modifying the system. The default chat model is
small enough for initial CPU testing; use `--model` to select a larger model.
`--install-dir` selects the WebUI installation location only, not Ollama's model
storage. It does not migrate data from a previous installation directory.

## Uninstall

The standard uninstall removes the `open-webui.service`, virtual environment,
and project-managed `uv` and Python files. It preserves Open WebUI user data and
all Ollama files:

```bash
./scripts/uninstall-local-llm.sh
```

Delete Open WebUI accounts, chats, document uploads, RAG indexes, and its secret
key only when they are no longer needed:

```bash
./scripts/uninstall-local-llm.sh --purge-data --yes
```

Use `--install-dir PATH` if installation used a custom directory. The uninstaller
validates the project's marker and the service's working directory before it
removes files. It does not remove Ubuntu packages, Ollama, or Ollama models.
