#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MODE=evaluation
APPLY_SYSCTL=false

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [evaluation|production] [--apply-sysctl]

evaluation  Starts SonarQube plus a same-host PostgreSQL container.
production  Starts SonarQube with the external database configured in .env.

The script creates a local password file when one does not exist. It never
stores the database password in .env or in the Compose model.
EOF
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    evaluation|production) MODE=$1; shift ;;
    -h|--help) usage; exit 0 ;;
  esac
fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply-sysctl) APPLY_SYSCTL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

command -v docker >/dev/null 2>&1 || { printf '%s\n' 'Docker is required.' >&2; exit 1; }
docker info >/dev/null 2>&1 || { printf '%s\n' 'Docker Engine is not reachable.' >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { printf '%s\n' 'Docker Compose v2 is required.' >&2; exit 1; }

cd "$SCRIPT_DIR"
if [ ! -f .env ]; then
  cp .env.example .env
  chmod 600 .env
  printf '%s\n' 'Created deployments/docker/.env from the example.'
fi

mkdir -p secrets
chmod 700 secrets
if [ ! -s secrets/jdbc_password ]; then
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 36 | tr -d '\015\012' >secrets/jdbc_password
  else
    umask 077
    od -An -N36 -tx1 /dev/urandom | tr -d ' \n' >secrets/jdbc_password
  fi
  chmod 600 secrets/jdbc_password
  printf '%s\n' 'Created a random database password in deployments/docker/secrets/.'
fi
secret_size=$(wc -c <secrets/jdbc_password | awk '{print $1}')
flat_size=$(tr -d '\015\012' <secrets/jdbc_password | wc -c | awk '{print $1}')
if [ "$secret_size" != "$flat_size" ]; then
  printf '%s\n' 'secrets/jdbc_password must not contain line endings; create it with printf, not echo.' >&2
  exit 1
fi

if [ "$(uname -s 2>/dev/null || true)" = Linux ]; then
  current_map_count=$(sysctl -n vm.max_map_count 2>/dev/null || printf '0')
  current_file_max=$(sysctl -n fs.file-max 2>/dev/null || printf '0')
  if [ "$current_map_count" -lt 524288 ] || [ "$current_file_max" -lt 131072 ]; then
    if [ "$APPLY_SYSCTL" = true ]; then
      command -v sudo >/dev/null 2>&1 || { printf '%s\n' 'sudo is required for --apply-sysctl.' >&2; exit 1; }
      sudo sysctl -w vm.max_map_count=524288 fs.file-max=131072 >/dev/null
    else
      printf '%s\n' \
        'Linux Elasticsearch limits are too low.' \
        'Re-run with --apply-sysctl or configure vm.max_map_count=524288 and fs.file-max=131072.' >&2
      exit 1
    fi
  fi
fi

if [ "$MODE" = production ]; then
  if grep -q 'postgresql\.example\.invalid' .env; then
    printf '%s\n' 'Set the external SONAR_JDBC_URL in deployments/docker/.env first.' >&2
    exit 1
  fi
  docker compose --env-file .env -f compose.yaml config --quiet
  docker compose --env-file .env -f compose.yaml up -d
else
  docker compose --env-file .env -f compose.yaml -f compose.local.yaml config --quiet
  docker compose --env-file .env -f compose.yaml -f compose.local.yaml up -d
fi

printf '%s\n' \
  'SonarQube is starting. Check with: docker compose ps' \
  'Open http://127.0.0.1:9000 and immediately change admin/admin.'
