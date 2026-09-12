#!/usr/bin/env bash
set -euo pipefail

MODEL="${MODEL:-qwen3:1.7b}"
EMBEDDING_MODEL="${EMBEDDING_MODEL:-nomic-embed-text}"
OPENWEBUI_DIR="${OPENWEBUI_DIR:-$HOME/open-webui}"
PYTHON_BIN="${PYTHON_BIN:-auto}"
WEBUI_HOST="${WEBUI_HOST:-127.0.0.1}"
WEBUI_PORT="${WEBUI_PORT:-8080}"
SHOW_CONFIG=false

usage() {
    cat <<'HELP'
Usage: install-local-llm.sh [options]

Install Ollama and Open WebUI on Ubuntu/Xubuntu with systemd.
Run as your normal user; privileged operations use sudo.
Internet access is required for packages and model downloads.

Options (built-in defaults shown):
  --model NAME             Chat model (qwen3:1.7b; small CPU-friendly default)
  --embedding-model NAME   RAG embedding model (nomic-embed-text)
  --install-dir PATH       Absolute WebUI directory ($HOME/open-webui)
  --python EXECUTABLE      Python 3.11/3.12 executable (auto)
  --host ADDRESS           127.0.0.1, or 0.0.0.0 for network access
  --port NUMBER            HTTP port (8080)
  --show-config            Print configuration and exit without installing
  -h, --help               Show this help and exit

Precedence: switches > environment variables > built-in defaults.
Environment: MODEL, EMBEDDING_MODEL, OPENWEBUI_DIR, PYTHON_BIN,
             WEBUI_HOST, WEBUI_PORT.

Examples:
  ./scripts/install-local-llm.sh
  ./scripts/install-local-llm.sh --python python3.11
  ./scripts/install-local-llm.sh --model gemma4:12b --port 8081

For network access, create the administrator account locally first,
then rerun with --host 0.0.0.0. Repeat custom settings on reruns.
--show-config validates options only; it does not check system prerequisites.
HELP
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --show-config) SHOW_CONFIG=true; shift ;;
        --model|--embedding-model|--install-dir|--python|--host|--port)
            [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || die "$1 requires a value"
            case "$1" in
                --model) MODEL="$2" ;;
                --embedding-model) EMBEDDING_MODEL="$2" ;;
                --install-dir) OPENWEBUI_DIR="$2" ;;
                --python) PYTHON_BIN="$2" ;;
                --host) WEBUI_HOST="$2" ;;
                --port) WEBUI_PORT="$2" ;;
            esac
            shift 2
            ;;
        *) die "Unknown argument: $1; see --help" ;;
    esac
done

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
[[ "$MODEL" =~ ^[a-zA-Z0-9][a-zA-Z0-9_./:-]*$ ]] || die 'MODEL contains unsupported characters.'
[[ "$EMBEDDING_MODEL" =~ ^[a-zA-Z0-9][a-zA-Z0-9_./:-]*$ ]] ||
    die 'EMBEDDING_MODEL contains unsupported characters.'

if "$SHOW_CONFIG"; then
    printf '%s\n' "MODEL=$MODEL" "EMBEDDING_MODEL=$EMBEDDING_MODEL" \
        "OPENWEBUI_DIR=$OPENWEBUI_DIR" "PYTHON_BIN=$PYTHON_BIN" \
        "WEBUI_HOST=$WEBUI_HOST" "WEBUI_PORT=$WEBUI_PORT"
    exit 0
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
if [[ "$PYTHON_BIN" != auto ]]; then
    command -v "$PYTHON_BIN" >/dev/null || die "Python executable not found: $PYTHON_BIN"
    PYTHON_BIN="$(command -v "$PYTHON_BIN")"
    "$PYTHON_BIN" -c 'import sys; sys.exit(sys.version_info[:2] not in ((3, 11), (3, 12)))' ||
        die 'The selected Python must be version 3.11 or 3.12.'
    "$PYTHON_BIN" -c 'import venv, ensurepip' ||
        die 'Install venv support for the selected Python first.'
fi

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
printf 'managed_by=local-llm-stack\n' > "$OPENWEBUI_DIR/.local-llm-stack"
if [[ -d "$OPENWEBUI_DIR/venv" ]]; then
    "$OPENWEBUI_DIR/venv/bin/python" -c 'import sys; sys.exit(sys.version_info[:2] not in ((3, 11), (3, 12)))' ||
        die 'Existing virtual environment has an unsupported Python version; use a new OPENWEBUI_DIR.'
else
    if [[ "$PYTHON_BIN" == auto ]] &&
        python3 -c 'import sys, venv, ensurepip; sys.exit(sys.version_info[:2] not in ((3, 11), (3, 12)))' 2>/dev/null; then
        PYTHON_BIN="$(command -v python3)"
        "$PYTHON_BIN" -m venv "$OPENWEBUI_DIR/venv"
    elif [[ "$PYTHON_BIN" == auto ]]; then
        UV_DIR="$OPENWEBUI_DIR/tools/uv"
        UV_BIN="$UV_DIR/uv"
        if [[ ! -x "$UV_BIN" ]]; then
            printf 'Installing uv to provision a local Python 3.11...\n'
            mkdir -p "$UV_DIR"
            uv_installer="$(mktemp)"
            trap 'rm -f -- "$uv_installer"' EXIT
            curl --fail --show-error --silent --location \
                https://astral.sh/uv/install.sh -o "$uv_installer"
            env UV_INSTALL_DIR="$UV_DIR" UV_NO_MODIFY_PATH=1 sh "$uv_installer"
            rm -f -- "$uv_installer"
            trap - EXIT
        fi
        "$UV_BIN" venv --python 3.11 "$OPENWEBUI_DIR/venv"
    else
        "$PYTHON_BIN" -m venv "$OPENWEBUI_DIR/venv"
    fi
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
