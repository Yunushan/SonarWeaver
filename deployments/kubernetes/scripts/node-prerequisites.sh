#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

MODE=check
SYSCTL_FILE=${SONARWEAVER_SYSCTL_FILE:-/etc/sysctl.d/99-sonarweaver.conf}
case "${1:-}" in
  '') ;;
  --check) MODE=check ;;
  --apply) MODE=apply ;;
  -h|--help)
    cat <<'EOF'
Usage: sudo ./node-prerequisites.sh [--check|--apply]

Run this on every Linux node eligible to host SonarQube. --apply persists the
required Elasticsearch kernel limits.
EOF
    exit 0
    ;;
  *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
esac

[ "$(uname -s)" = Linux ] || { printf '%s\n' 'Linux nodes are required.' >&2; exit 1; }

if [ "$MODE" = apply ]; then
  [ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Run --apply as root.' >&2; exit 1; }
  map_count=$(sysctl -n vm.max_map_count 2>/dev/null || printf '0')
  file_max=$(sysctl -n fs.file-max 2>/dev/null || printf '0')
  [ "$map_count" -ge 524288 ] 2>/dev/null || map_count=524288
  [ "$file_max" -ge 131072 ] 2>/dev/null || file_max=131072
  {
    printf '%s\n' '# Managed by SonarWeaver.'
    printf 'vm.max_map_count=%s\n' "$map_count"
    printf 'fs.file-max=%s\n' "$file_max"
  } >"$SYSCTL_FILE"
  chmod 0644 "$SYSCTL_FILE"
  sysctl -p "$SYSCTL_FILE" >/dev/null
fi

failed=false
check_value() {
  name=$1
  required=$2
  actual=$(sysctl -n "$name" 2>/dev/null || printf '0')
  if [ "$actual" -lt "$required" ] 2>/dev/null; then
    printf 'FAIL %-18s actual=%s required>=%s\n' "$name" "$actual" "$required"
    failed=true
  else
    printf 'PASS %-18s actual=%s\n' "$name" "$actual"
  fi
}

check_value vm.max_map_count 524288
check_value fs.file-max 131072

if [ ! -r "/boot/config-$(uname -r)" ]; then
  printf '%s\n' 'WARN Kernel config is unavailable; verify that seccomp filtering is enabled.'
elif grep -q '^CONFIG_SECCOMP=y' "/boot/config-$(uname -r)" && \
     grep -q '^CONFIG_SECCOMP_FILTER=y' "/boot/config-$(uname -r)"; then
  printf '%s\n' 'PASS seccomp filtering is enabled.'
else
  printf '%s\n' 'FAIL seccomp filtering is not enabled.'
  failed=true
fi

[ "$failed" = false ] || exit 1
printf '%s\n' 'Node prerequisites are satisfied.'
