#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

run_contract_test() {
  output=$(mktemp "${TMPDIR:-/tmp}/sonarweaver-smoke.XXXXXX")
  if "$@" >"$output" 2>&1; then
    rm -f "$output"
    return 0
  fi
  cat "$output" >&2
  rm -f "$output"
  return 1
}

"$ROOT/bin/sonarweaver" --help >/dev/null
"$ROOT/bin/sonarweaver" version | grep -q '^SonarWeaver '
"$ROOT/deployments/native/linux/install.sh" --help >/dev/null
"$ROOT/deployments/native/macos/install.sh" --help >/dev/null
"$ROOT/deployments/native/unix/preflight.sh" >/dev/null
"$ROOT/deployments/docker/bootstrap.sh" --help >/dev/null
"$ROOT/deployments/verify-production.sh" --help >/dev/null
"$ROOT/deployments/kubernetes/scripts/install.sh" --help >/dev/null
"$ROOT/deployments/kubernetes/scripts/node-prerequisites.sh" --help >/dev/null
run_contract_test "$ROOT/tests/kubernetes-installer.sh"
run_contract_test "$ROOT/tests/linux-installer.sh"
run_contract_test "$ROOT/tests/native-verification.sh"
run_contract_test "$ROOT/tests/docker-bootstrap.sh"
run_contract_test "$ROOT/tests/docker-status.sh"
run_contract_test "$ROOT/tests/node-prerequisites.sh"
run_contract_test "$ROOT/tests/ignore-policy.sh"
run_contract_test "$ROOT/tests/verify-production.sh"

community_version=$(sed -n 's/^SONARQUBE_COMMUNITY_VERSION="\([^"]*\)"$/\1/p' "$ROOT/config/versions.env")
ansible_version=$(sed -n 's/^sonarweaver_version: "\([^"]*\)"$/\1/p' "$ROOT/ansible/group_vars/all/main.yml")
[ -n "$community_version" ] || { printf '%s\n' 'Missing Community Build version pin.' >&2; exit 1; }
[ "$community_version" = "$ansible_version" ] || {
  printf '%s\n' 'Ansible default version must match config/versions.env.' >&2
  exit 1
}

postgres_image=$(sed -n 's/^POSTGRES_IMAGE="\([^\"]*\)"$/\1/p' "$ROOT/config/versions.env")
case "$postgres_image" in postgres@sha256:[0-9a-f][0-9a-f]*) ;; *)
  printf '%s\n' 'PostgreSQL image must use an immutable digest.' >&2
  exit 1
  ;;
esac

sonarqube_image=$(sed -n 's/^SONARQUBE_DOCKER_IMAGE="\([^\"]*\)"$/\1/p' "$ROOT/config/versions.env")
case "$sonarqube_image" in sonarqube@sha256:[0-9a-f][0-9a-f]*) ;; *)
  printf '%s\n' 'SonarQube Docker image must use an immutable digest.' >&2
  exit 1
  ;;
esac

compose_sonarqube_image=$(sed -n 's/^SONARQUBE_IMAGE=\(.*\)$/\1/p' "$ROOT/deployments/docker/.env.example")
compose_postgres_image=$(sed -n 's/^POSTGRES_IMAGE=\(.*\)$/\1/p' "$ROOT/deployments/docker/.env.example")
[ "$compose_sonarqube_image" = "$sonarqube_image" ] || {
  printf '%s\n' 'Compose SonarQube image must match the central digest lock.' >&2
  exit 1
}
[ "$compose_postgres_image" = "$postgres_image" ] || {
  printf '%s\n' 'Compose PostgreSQL image must match the central digest lock.' >&2
  exit 1
}

grep -q '^Permission to use, copy, modify, and/or distribute this software for any$' "$ROOT/LICENSE"
printf '%s\n' 'Static smoke checks passed.'
