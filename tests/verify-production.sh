#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
VERIFY="$ROOT/deployments/verify-production.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sonarweaver-verify-test.XXXXXX")
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT HUP INT TERM
mkdir "$TEST_ROOT/bin"
printf '%s' 'monitoring-passcode' >"$TEST_ROOT/passcode"

cat >"$TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env sh
set -eu

case " $* " in *' monitoring-passcode '*)
  printf '%s\n' 'Passcode leaked into curl arguments.' >&2
  exit 1
  ;;
esac

case "$*" in
  *'/api/system/status'*) printf '%s\n' '{"status":"UP"}' ;;
  *'/api/monitoring/metrics'*)
    config=
    previous=
    for argument in "$@"; do
      if [ "$previous" = --config ]; then config=$argument; break; fi
      previous=$argument
    done
    grep -qx 'header = "X-Sonar-Passcode: monitoring-passcode"' "$config"
    printf '%s\n' '# HELP sonarweaver_test 1' 'sonarweaver_test 1'
    ;;
  *) printf '%s\n' 'Unexpected curl request.' >&2; exit 1 ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/curl"

PATH="$TEST_ROOT/bin:$PATH" "$VERIFY" \
  --url https://sonarqube.example \
  --monitoring-passcode-file "$TEST_ROOT/passcode" >/dev/null

if PATH="$TEST_ROOT/bin:$PATH" "$VERIFY" \
  --url http://sonarqube.example \
  --monitoring-passcode-file "$TEST_ROOT/passcode" >/dev/null 2>&1; then
  printf '%s\n' 'Production verification unexpectedly accepted HTTP.' >&2
  exit 1
fi

printf '%s\n' 'Production verification contract tests passed.'
