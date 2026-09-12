# Installing the local LLM stack

The installer supports Ubuntu/Xubuntu 22.04 and 24.04 with systemd.
Run it as your normal user. It uses sudo for package and service changes.
Internet access and sufficient storage for Python dependencies and models are
required. Model performance depends on available RAM and GPU hardware.

Before running, install Python 3.11 or 3.12 with its matching venv support.
Ubuntu 24.04 users can install the distribution packages:

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv
./scripts/install-local-llm.sh
```

Ubuntu 22.04's default Python is unsuitable. Provide an independently installed
Python 3.11 or 3.12 with venv support; do not replace the system interpreter:

```bash
PYTHON_BIN=python3.11 ./scripts/install-local-llm.sh
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
WEBUI_HOST=0.0.0.0 ./scripts/install-local-llm.sh
```

This exposes HTTP on all IPv4 interfaces reachable through your firewall. Use
appropriate access controls and HTTPS when deploying beyond a trusted local host.

Configuration is supplied through environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `EMBEDDING_MODEL` | `nomic-embed-text` | Local Ollama embedding model for RAG |
| `MODEL` | `gemma4:12b` | Model downloaded through Ollama |
| `OPENWEBUI_DIR` | `$HOME/open-webui` | Absolute installation directory |
| `PYTHON_BIN` | `python3` | Python 3.11 or 3.12 executable |
| `WEBUI_HOST` | `127.0.0.1` | Local binding, or `0.0.0.0` for network access |
| `WEBUI_PORT` | `8080` | HTTP port |

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
