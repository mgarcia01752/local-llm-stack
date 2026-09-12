#!/usr/bin/env bash
set -euo pipefail

MODEL="${MODEL:-gemma4:12b}"
EMBEDDING_MODEL="${EMBEDDING_MODEL:-nomic-embed-text}"
OPENWEBUI_DIR="${OPENWEBUI_DIR:-$HOME/open-webui}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
WEBUI_HOST="${WEBUI_HOST:-127.0.0.1}"
WEBUI_PORT="${WEBUI_PORT:-8080}"

usage() {
    cat <<'HELP'
Usage: install-local-llm.sh [--help]

Install Ollama and Open WebUI on Ubuntu/Xubuntu with systemd.
Run as your normal user; privileged operations use sudo.
Internet access is required for packages and model downloads.

Environment variables:
  MODEL           Ollama model (default: gemma4:12b)
  EMBEDDING_MODEL Local RAG embedding model (default: nomic-embed-text)
  OPENWEBUI_DIR   Absolute installation directory (default: $HOME/open-webui)
  PYTHON_BIN      Python 3.11 or 3.12 executable (default: python3)
  WEBUI_HOST      127.0.0.1 (default), or 0.0.0.0 for network access
  WEBUI_PORT      HTTP port (default: 8080)

For network access, create the administrator account locally first,
then rerun with WEBUI_HOST=0.0.0.0.
HELP
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ $# -gt 0 ]]; then
    [[ $# -eq 1 ]] || die 'Unexpected arguments; see --help'
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1; see --help" ;;
    esac
fi

# Validate before changing packages or services.
[[ $EUID -ne 0 ]] || die 'Run as your normal user, without sudo.'
[[ -r /etc/os-release ]] || die 'Cannot identify this operating system.'
# shellcheck source=/dev/null
source /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die 'Only Ubuntu/Xubuntu is supported.'
case "${VERSION_ID:-}" in
    22.04|24.04) ;;
    *) die 'Supported Ubuntu releases: 22.04 and 24.04.' ;;
esac
[[ -d /run/systemd/system ]] || die 'A running systemd system is required.'
command -v sudo >/dev/null || die 'sudo is required.'
command -v "$PYTHON_BIN" >/dev/null || die "Python executable not found: $PYTHON_BIN"
PYTHON_BIN="$(command -v "$PYTHON_BIN")"
"$PYTHON_BIN" -c 'import sys; sys.exit(sys.version_info[:2] not in ((3, 11), (3, 12)))' ||
    die 'Select an installed Python 3.11 or 3.12 using PYTHON_BIN.'
"$PYTHON_BIN" -c 'import venv, ensurepip' ||
    die 'Install the venv support package for the selected Python first.'
[[ "$OPENWEBUI_DIR" == /* && "$OPENWEBUI_DIR" != / ]] || die 'OPENWEBUI_DIR must be an absolute directory other than /.'
# Keep paths safe for direct use in systemd unit directives.
[[ "$OPENWEBUI_DIR" =~ ^/[a-zA-Z0-9_./-]+$ ]] || die 'OPENWEBUI_DIR contains unsupported characters.'
case "$WEBUI_HOST" in
    127.0.0.1|0.0.0.0) ;;
    *) die 'WEBUI_HOST must be 127.0.0.1 or 0.0.0.0.' ;;
esac
[[ "$WEBUI_PORT" =~ ^[0-9]{1,5}$ ]] || die 'WEBUI_PORT must be an integer from 1 to 65535.'
WEBUI_PORT=$((10#$WEBUI_PORT))
(( WEBUI_PORT >= 1 && WEBUI_PORT <= 65535 )) || die 'WEBUI_PORT must be from 1 to 65535.'
[[ -n "$MODEL" && "$MODEL" != -* ]] || die 'MODEL must be a model name.'

wait_for_http() {
    local service="$1" url="$2" attempts="$3"
    local attempt
    for ((attempt = 0; attempt < attempts; attempt++)); do
        if curl --noproxy '*' --fail --silent --max-time 2 "$url" >/dev/null; then
            return 0
        fi
        sleep 2
    done
    sudo journalctl -u "$service" -n 30 --no-pager >&2 || true
    die "$service did not become ready at $url"
}

[[ "$EMBEDDING_MODEL" =~ ^[a-zA-Z0-9][a-zA-Z0-9_./:-]*$ ]] ||
    die 'EMBEDDING_MODEL contains unsupported characters.'

sudo -v
printf '[1/6] Installing dependencies...\n'
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates

printf '[2/6] Installing Ollama...\n'
if ! command -v ollama >/dev/null 2>&1; then
    installer="$(mktemp)"
    trap 'rm -f -- "$installer"' EXIT
    curl --fail --show-error --silent --location https://ollama.com/install.sh -o "$installer"
    sh "$installer"
    rm -f -- "$installer"
    trap - EXIT
fi
sudo systemctl enable --now ollama
wait_for_http ollama http://127.0.0.1:11434/api/tags 60

printf '[3/6] Installing Open WebUI...\n'
mkdir -p "$OPENWEBUI_DIR"
OPENWEBUI_DIR="$(cd -- "$OPENWEBUI_DIR" && pwd -P)"
[[ "$OPENWEBUI_DIR" =~ ^/[a-zA-Z0-9_./-]+$ ]] || die 'Resolved installation path contains unsupported characters.'
if [[ -d "$OPENWEBUI_DIR/venv" ]]; then
    "$OPENWEBUI_DIR/venv/bin/python" -c 'import sys; sys.exit(sys.version_info[:2] not in ((3, 11), (3, 12)))' ||
        die 'Existing virtual environment has an unsupported Python version; use a new OPENWEBUI_DIR.'
else
    "$PYTHON_BIN" -m venv "$OPENWEBUI_DIR/venv"
fi
"$OPENWEBUI_DIR/venv/bin/python" -m pip install open-webui
mkdir -p "$OPENWEBUI_DIR/data"

printf 'Downloading RAG embedding model: %s\n' "$EMBEDDING_MODEL"
OLLAMA_HOST=http://127.0.0.1:11434 ollama pull "$EMBEDDING_MODEL"

printf '[4/6] Configuring Open WebUI service...\n'
USER_NAME="$(id -un)"
sudo tee /etc/systemd/system/open-webui.service >/dev/null <<UNIT
[Unit]
Description=Open WebUI
After=network.target ollama.service
Requires=ollama.service

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$OPENWEBUI_DIR
Environment="DATA_DIR=$OPENWEBUI_DIR/data"
Environment="OLLAMA_BASE_URL=http://127.0.0.1:11434"
Environment="RAG_EMBEDDING_ENGINE=ollama"
Environment="RAG_EMBEDDING_MODEL=$EMBEDDING_MODEL"
Environment="RAG_OLLAMA_BASE_URL=http://127.0.0.1:11434"
ExecStart=$OPENWEBUI_DIR/venv/bin/open-webui serve --host $WEBUI_HOST --port $WEBUI_PORT
Restart=on-failure
RestartSec=5
UMask=0077

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable open-webui
sudo systemctl restart open-webui
wait_for_http open-webui "http://127.0.0.1:$WEBUI_PORT/health" 150

printf '[5/6] Downloading model: %s\n' "$MODEL"
OLLAMA_HOST=http://127.0.0.1:11434 ollama pull "$MODEL"

printf '[6/6] Checking services...\n'
sudo systemctl is-active --quiet ollama open-webui || die 'A required service is not active.'
wait_for_http open-webui "http://127.0.0.1:$WEBUI_PORT/health" 5
printf '\nInstallation complete. Open http://localhost:%s\n' "$WEBUI_PORT"
printf 'Run the model: OLLAMA_HOST=http://127.0.0.1:11434 ollama run %s\n' "$MODEL"
printf 'RAG: verify Ollama embeddings (%s) in Admin Settings > Documents before uploading files.\n' "$EMBEDDING_MODEL"
