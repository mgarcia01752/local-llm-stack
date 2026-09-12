#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
COMMIT_MSG=""

usage() {
  cat <<'EOF'
Usage: git-save.sh --commit-msg <message>

Stage all changes in the project and create a Git commit.

Options:
  --commit-msg <message>  Required commit message.
  -h, --help              Show this help and exit.

Example:
  tools/git/git-save.sh --commit-msg "Feature: Add setup modules"
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit-msg)
      [[ $# -ge 2 ]] || die "--commit-msg requires a message"
      COMMIT_MSG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
done

[[ -n "${COMMIT_MSG}" ]] || die "--commit-msg is required"
git -C "${PROJECT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
  die "Project directory is not a Git working tree: ${PROJECT_DIR}"

git -C "${PROJECT_DIR}" add --all

if git -C "${PROJECT_DIR}" diff --cached --quiet; then
  die "No staged changes to commit"
fi

echo "Staged changes:"
git -C "${PROJECT_DIR}" diff --cached --stat
echo
echo "Commit message: ${COMMIT_MSG}"

git -C "${PROJECT_DIR}" commit -m "${COMMIT_MSG}"
