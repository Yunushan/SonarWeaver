#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HELPER="$ROOT/deployments/kubernetes/scripts/node-prerequisites.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sonarweaver-node-prerequisites.XXXXXX")
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT HUP INT TERM
mkdir "$TEST_ROOT/bin"

cat >"$TEST_ROOT/bin/uname" <<'EOF'
#!/usr/bin/env sh
case "${1:-}" in -s) printf '%s\n' Linux ;; -r) printf '%s\n' sonarweaver-test ;; *) exit 1 ;; esac
EOF
cat >"$TEST_ROOT/bin/id" <<'EOF'
#!/usr/bin/env sh
case "${1:-}" in -u) printf '%s\n' 0 ;; *) exit 1 ;; esac
EOF
cat >"$TEST_ROOT/bin/sysctl" <<'EOF'
#!/usr/bin/env sh
set -eu

case "${1:-}" in
  -n)
    case "${2:-}" in
      vm.max_map_count) printf '%s\n' "${SONARWEAVER_TEST_MAP_COUNT:-524288}" ;;
      fs.file-max) printf '%s\n' "${SONARWEAVER_TEST_FILE_MAX:-131072}" ;;
      *) exit 1 ;;
    esac
    ;;
  -p) printf '%s\n' "${2:-}" >>"$SONARWEAVER_TEST_SYSCTL_LOAD_LOG" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/uname" "$TEST_ROOT/bin/id" "$TEST_ROOT/bin/sysctl"

: >"$TEST_ROOT/sysctl-load.log"
PATH="$TEST_ROOT/bin:$PATH" \
  SONARWEAVER_TEST_SYSCTL_LOAD_LOG="$TEST_ROOT/sysctl-load.log" \
  "$HELPER" --check >/dev/null

if PATH="$TEST_ROOT/bin:$PATH" \
  SONARWEAVER_TEST_MAP_COUNT=1 \
  SONARWEAVER_TEST_SYSCTL_LOAD_LOG="$TEST_ROOT/sysctl-load.log" \
  "$HELPER" --check >/dev/null 2>&1; then
  printf '%s\n' 'Node prerequisite check unexpectedly accepted a low vm.max_map_count.' >&2
  exit 1
fi

sysctl_file="$TEST_ROOT/99-sonarweaver.conf"
PATH="$TEST_ROOT/bin:$PATH" \
  SONARWEAVER_SYSCTL_FILE="$sysctl_file" \
  SONARWEAVER_TEST_SYSCTL_LOAD_LOG="$TEST_ROOT/sysctl-load.log" \
  "$HELPER" --apply >/dev/null

grep -qx 'vm.max_map_count=524288' "$sysctl_file"
grep -qx 'fs.file-max=131072' "$sysctl_file"
grep -qx "$sysctl_file" "$TEST_ROOT/sysctl-load.log"

printf '%s\n' 'Node prerequisite tests passed.'
