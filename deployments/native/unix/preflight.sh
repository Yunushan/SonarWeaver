#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

os=$(uname -s 2>/dev/null || printf unknown)
arch=$(uname -m 2>/dev/null || printf unknown)

printf 'Detected operating system: %s\n' "$os"
printf 'Detected architecture: %s\n' "$arch"

case "$os" in
  Linux)
    printf '%s\n' 'Supported upstream. Use deployments/native/linux/install.sh.'
    ;;
  Darwin)
    printf '%s\n' 'Supported upstream. Use deployments/native/macos/install.sh.'
    ;;
  FreeBSD|OpenBSD|NetBSD|SunOS|AIX|HP-UX)
    printf '%s\n' \
      "SonarSource does not list $os as a supported native SonarQube host." \
      'SonarWeaver will not launch an upstream binary on an unverified platform.' \
      'Use a supported Linux VM, or a supported Linux container platform where available.' >&2
    exit 2
    ;;
  *)
    printf 'Unknown or unsupported Unix-family platform: %s\n' "$os" >&2
    exit 2
    ;;
esac
