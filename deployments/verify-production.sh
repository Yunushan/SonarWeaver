#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

URL=
PASSCODE_FILE=

usage() {
  cat <<'EOF'
Usage: ./verify-production.sh --url https://sonarqube.example --monitoring-passcode-file PATH

Verifies the HTTPS API health response and authenticated monitoring endpoint.
The passcode is read through a temporary curl config file so it is not exposed
in command arguments.
EOF
}

need_value() { [ "$#" -ge 2 ] || { printf '%s requires a value.\n' "$1" >&2; exit 1; }; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) need_value "$@"; URL=$2; shift 2 ;;
    --monitoring-passcode-file) need_value "$@"; PASSCODE_FILE=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

case "$URL" in https://?*) ;; *) printf '%s\n' '--url must use HTTPS.' >&2; exit 1 ;; esac
if ! { [ -r "$PASSCODE_FILE" ] && [ -s "$PASSCODE_FILE" ]; }; then
  printf '%s\n' '--monitoring-passcode-file must be a readable, non-empty file.' >&2
  exit 1
fi
command -v curl >/dev/null 2>&1 || { printf '%s\n' 'curl is required.' >&2; exit 1; }

passcode=$(cat "$PASSCODE_FILE")
file_size=$(wc -c <"$PASSCODE_FILE" | awk '{print $1}')
flat_size=$(tr -d '\015\012' <"$PASSCODE_FILE" | wc -c | awk '{print $1}')
case "$passcode" in *\"*|*\\*)
  printf '%s\n' 'Monitoring passcode must not contain quote or backslash characters.' >&2
  exit 1
  ;;
esac
[ "$file_size" = "$flat_size" ] || {
  printf '%s\n' 'Monitoring passcode must not contain a line ending.' >&2
  exit 1
}

curl_config=$(mktemp "${TMPDIR:-/tmp}/sonarweaver-curl.XXXXXX")
cleanup() { rm -f "$curl_config"; }
trap cleanup EXIT HUP INT TERM
chmod 600 "$curl_config"
printf 'header = "X-Sonar-Passcode: %s"\n' "$passcode" >"$curl_config"

status=$(curl --fail --silent --show-error --proto '=https' --tlsv1.2 "$URL/api/system/status")
printf '%s' "$status" | tr -d '[:space:]' | grep -q '"status":"UP"' || {
  printf '%s\n' 'SonarQube did not report system status UP.' >&2
  exit 1
}

metrics=$(curl --config "$curl_config" --fail --silent --show-error --proto '=https' --tlsv1.2 "$URL/api/monitoring/metrics")
[ -n "$metrics" ] || { printf '%s\n' 'Monitoring endpoint returned no metrics.' >&2; exit 1; }
printf '%s\n' 'Production HTTPS, health, and monitoring checks passed.'
