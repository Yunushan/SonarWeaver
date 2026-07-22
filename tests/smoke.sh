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

grep -q '^Permission to use, copy, modify, and/or distribute this software for any$' "$ROOT/LICENSE"
printf '%s\n' 'Static smoke checks passed.'
