#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../deployments/native/common.sh
. "$ROOT/deployments/native/common.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sonarweaver-native-verification.XXXXXX")
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT HUP INT TERM

archive="$TEST_ROOT/sonarqube.zip"
printf '%s' 'trusted test archive' >"$archive"
trusted_sha256=$(sha256_file "$archive")

verify_archive "$archive" "$TEST_ROOT/unused.asc" "$trusted_sha256"

if (verify_archive "$archive" "$TEST_ROOT/unused.asc" \
  0000000000000000000000000000000000000000000000000000000000000000); then
  printf '%s\n' 'Archive verification unexpectedly accepted an incorrect checksum.' >&2
  exit 1
fi

if (verify_archive "$archive" "$TEST_ROOT/unused.asc" not-a-checksum); then
  printf '%s\n' 'Archive verification unexpectedly accepted a malformed checksum.' >&2
  exit 1
fi

printf '%s\n' 'Native archive verification tests passed.'
