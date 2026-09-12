#!/usr/bin/env bash
set -euo pipefail

OPENWEBUI_DIR="${OPENWEBUI_DIR:-$HOME/open-webui}"
PURGE_DATA=false
ASSUME_YES=false

usage() {
    cat <<'HELP'
Usage: uninstall-local-llm.sh [options]

Remove the Open WebUI service and runtime installed by this repository.
Ollama, downloaded models, system packages, and user data are preserved by
default.

Options:
  --install-dir PATH  Open WebUI directory ($HOME/open-webui)
  --purge-data        Also remove chats, accounts, RAG data, and secret key
  --yes               Confirm permanent data deletion with --purge-data
  -h, --help          Show this help and exit

The installation directory must contain this project's marker file. If the
installer used a custom --install-dir, pass the same path here.
HELP
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --purge-data) PURGE_DATA=true; shift ;;
        --yes) ASSUME_YES=true; shift ;;
        --install-dir)
            [[ $# -ge 2 && -n "$2" && "$2" != -* ]] ||
                die '--install-dir requires a value'
            OPENWEBUI_DIR="$2"
            shift 2
            ;;
        *) die "Unknown argument: $1; see --help" ;;
    esac
done

[[ $EUID -ne 0 ]] || die 'Run as your normal user, without sudo.'
command -v sudo >/dev/null || die 'sudo is required.'
[[ -d /run/systemd/system ]] || die 'A running systemd system is required.'
[[ "$OPENWEBUI_DIR" == /* && "$OPENWEBUI_DIR" != / ]] ||
    die 'OPENWEBUI_DIR must be an absolute directory other than /.'
[[ "$OPENWEBUI_DIR" =~ ^/[a-zA-Z0-9_./-]+$ ]] ||
    die 'OPENWEBUI_DIR contains unsupported characters.'
[[ -d "$OPENWEBUI_DIR" ]] || die "Installation directory does not exist: $OPENWEBUI_DIR"
OPENWEBUI_DIR="$(cd -- "$OPENWEBUI_DIR" && pwd -P)"
MARKER="$OPENWEBUI_DIR/.local-llm-stack"
[[ -f "$MARKER" ]] || die "Project installation marker not found: $MARKER"
grep -Fxq 'managed_by=local-llm-stack' "$MARKER" ||
    die "Invalid project installation marker: $MARKER"

if "$PURGE_DATA" && ! "$ASSUME_YES"; then
    die '--purge-data permanently deletes chats and RAG data; add --yes to confirm'
fi

SERVICE_FILE=/etc/systemd/system/open-webui.service
if [[ -f "$SERVICE_FILE" ]] &&
    ! grep -Fxq "WorkingDirectory=$OPENWEBUI_DIR" "$SERVICE_FILE"; then
    die "$SERVICE_FILE is not associated with $OPENWEBUI_DIR"
fi

sudo -v
if systemctl list-unit-files open-webui.service --no-legend 2>/dev/null |
    grep -q '^open-webui.service'; then
    sudo systemctl disable --now open-webui.service
fi
if [[ -f "$SERVICE_FILE" ]]; then
    sudo rm -f -- "$SERVICE_FILE"
    sudo systemctl daemon-reload
fi

rm -rf -- "$OPENWEBUI_DIR/venv" "$OPENWEBUI_DIR/tools"

if "$PURGE_DATA"; then
    rm -rf -- "$OPENWEBUI_DIR/data"
    rm -f -- "$OPENWEBUI_DIR/.webui_secret_key" "$MARKER"
    rmdir -- "$OPENWEBUI_DIR" 2>/dev/null || true
    printf 'Open WebUI runtime and managed user data removed.\n'
else
    printf 'Open WebUI runtime removed. User data remains in %s/data.\n' \
        "$OPENWEBUI_DIR"
    printf 'Ollama and its downloaded models were preserved.\n'
fi
