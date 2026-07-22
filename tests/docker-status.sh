#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sonarweaver-docker-status.XXXXXX")
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT HUP INT TERM
mkdir "$TEST_ROOT/bin"

cat >"$TEST_ROOT/bin/docker" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >"$SONARWEAVER_DOCKER_STATUS_LOG"
EOF
chmod +x "$TEST_ROOT/bin/docker"
STATUS_LOG="$TEST_ROOT/status.log"

PATH="$TEST_ROOT/bin:$PATH" SONARWEAVER_DOCKER_STATUS_LOG="$STATUS_LOG" \
  "$ROOT/bin/sonarweaver" status docker evaluation
grep -qx 'compose --env-file .env -f compose.yaml -f compose.local.yaml ps' "$STATUS_LOG"

PATH="$TEST_ROOT/bin:$PATH" SONARWEAVER_DOCKER_STATUS_LOG="$STATUS_LOG" \
  "$ROOT/bin/sonarweaver" status docker production
grep -qx 'compose --env-file .env -f compose.yaml ps' "$STATUS_LOG"

PATH="$TEST_ROOT/bin:$PATH" SONARWEAVER_DOCKER_STATUS_LOG="$STATUS_LOG" \
  "$ROOT/bin/sonarweaver" status docker production --all
grep -qx 'compose --env-file .env -f compose.yaml ps --all' "$STATUS_LOG"

if PATH="$TEST_ROOT/bin:$PATH" SONARWEAVER_DOCKER_STATUS_LOG="$STATUS_LOG" \
  "$ROOT/bin/sonarweaver" status docker invalid >/dev/null 2>&1; then
  printf '%s\n' 'Docker status unexpectedly accepted an invalid deployment mode.' >&2
  exit 1
fi

printf '%s\n' 'Docker status mode tests passed.'
