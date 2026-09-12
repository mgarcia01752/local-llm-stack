#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
REMOTE="origin"

usage() {
  cat <<'EOF'
Usage: git-push.sh

Push the clean project main/master branch to origin.

Safety checks:
  - The working tree must have no tracked or untracked changes.
  - The current branch must be main or master.
  - The origin remote must exist.
  - The local branch must not be behind or diverged from origin.
  - Force-push is never used.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ $# -le 1 ]] || die "Unexpected extra arguments (see --help)"

case "${1:-}" in
  "") ;;
  -h|--help)
    usage
    exit 0
    ;;
  *) die "Unknown argument: $1 (see --help)" ;;
esac

git -C "${PROJECT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
  die "Project directory is not a Git working tree: ${PROJECT_DIR}"

if [[ -n "$(git -C "${PROJECT_DIR}" status --porcelain)" ]]; then
  git -C "${PROJECT_DIR}" status --short >&2
  die "Working tree is not clean; commit or remove changes first"
fi

branch="$(git -C "${PROJECT_DIR}" branch --show-current)"
case "${branch}" in
  main|master) ;;
  "") die "HEAD is detached; check out main or master first" ;;
  *) die "Refusing to push branch '${branch}'; use main or master" ;;
esac

git -C "${PROJECT_DIR}" remote get-url "${REMOTE}" >/dev/null 2>&1 || \
  die "Remote '${REMOTE}' is not configured"

if [[ -n "$(git -C "${PROJECT_DIR}" ls-remote --heads \
    "${REMOTE}" "refs/heads/${branch}")" ]]; then
  echo "Fetching ${REMOTE}/${branch}..."
  git -C "${PROJECT_DIR}" fetch "${REMOTE}" "${branch}"
  remote_ref="FETCH_HEAD"

  git -C "${PROJECT_DIR}" merge-base --is-ancestor \
    "${remote_ref}" HEAD || \
    die "Local ${branch} is behind or diverged from ${remote_ref}"
else
  echo "Remote branch ${REMOTE}/${branch} does not exist; creating it."
fi

echo "Pushing ${branch} to ${REMOTE}..."
git -C "${PROJECT_DIR}" push --set-upstream "${REMOTE}" "${branch}"
