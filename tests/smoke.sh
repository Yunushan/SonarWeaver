#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

"$ROOT/bin/sonarweaver" --help >/dev/null
"$ROOT/bin/sonarweaver" version | grep -q '^SonarWeaver '
"$ROOT/deployments/native/linux/install.sh" --help >/dev/null
"$ROOT/deployments/native/macos/install.sh" --help >/dev/null
"$ROOT/deployments/native/unix/preflight.sh" >/dev/null
"$ROOT/deployments/docker/bootstrap.sh" --help >/dev/null
"$ROOT/deployments/kubernetes/scripts/install.sh" --help >/dev/null
"$ROOT/deployments/kubernetes/scripts/node-prerequisites.sh" --help >/dev/null
"$ROOT/tests/kubernetes-installer.sh" >/dev/null

community_version=$(sed -n 's/^SONARQUBE_COMMUNITY_VERSION="\([^"]*\)"$/\1/p' "$ROOT/config/versions.env")
ansible_version=$(sed -n 's/^sonarweaver_version: "\([^"]*\)"$/\1/p' "$ROOT/ansible/group_vars/all/main.yml")
[ -n "$community_version" ] || { printf '%s\n' 'Missing Community Build version pin.' >&2; exit 1; }
[ "$community_version" = "$ansible_version" ] || {
  printf '%s\n' 'Ansible default version must match config/versions.env.' >&2
  exit 1
}

grep -q '^Permission to use, copy, modify, and/or distribute this software for any$' "$ROOT/LICENSE"
printf '%s\n' 'Static smoke checks passed.'
