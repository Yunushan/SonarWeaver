#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
ignore_file=.gitignore

for private_rule in \
  '.env' \
  '**/secrets/*' \
  'ansible/inventory/*' \
  'ansible/group_vars/**/vault.yml' \
  'ansible/group_vars/**/*.vault*'; do
  grep -Fqx -- "$private_rule" "$ignore_file" || {
    printf 'Expected private ignore rule is missing: %s\n' "$private_rule" >&2
    exit 1
  }
done

for example_rule in \
  '!.env.example' \
  '!**/secrets/*.example' \
  '!ansible/inventory/*.example.yml'; do
  grep -Fqx -- "$example_rule" "$ignore_file" || {
    printf 'Expected example allow rule is missing: %s\n' "$example_rule" >&2
    exit 1
  }
done

printf '%s\n' 'Ignore policy tests passed.'
