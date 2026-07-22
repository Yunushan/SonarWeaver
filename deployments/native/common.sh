#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

SONAR_SOURCE_KEY="679F1EE92B19609DE816FDE81DB198F93525EC1A"
SONAR_SOURCE_KEYSERVER="hkps://keyserver.ubuntu.com"

log() {
  printf '%s\n' "[sonarweaver] $*" >&2
}

warn() {
  printf '%s\n' "[sonarweaver] WARNING: $*" >&2
}

die() {
  printf '%s\n' "[sonarweaver] ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

validate_version() {
  case "$1" in
    '' | *[!0-9A-Za-z._-]*) die "Invalid version: $1" ;;
  esac
}

validate_secret_file() {
  label=$1
  file=$2
  [ -r "$file" ] || die "Cannot read $label: $file"
  [ -s "$file" ] || die "$label is empty."
  file_size=$(wc -c <"$file" | awk '{print $1}')
  flat_size=$(tr -d '\015\012' <"$file" | wc -c | awk '{print $1}')
  [ "$file_size" = "$flat_size" ] || \
    die "$label must not contain line endings; create it with printf, not echo."
}

java_major() {
  java -version 2>&1 | awk -F '[\".]' '/version/ { print $2; exit }'
}

check_java() {
  require_command java
  major=$(java_major)
  case " $JAVA_SUPPORTED_MAJORS " in
    *" $major "*) log "Java $major is supported." ;;
    *) die "Java $major is unsupported; install a current JDK 21 or 25 CPU release." ;;
  esac
}

download_file() {
  url=$1
  destination=$2
  if command -v curl >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
      --output "$destination" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget --https-only --output-document="$destination" "$url"
  else
    die "Install curl or wget."
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "No SHA-256 utility found (sha256sum or shasum)."
  fi
}

verify_archive() {
  archive=$1
  signature=$2
  expected_sha256=${3:-}

  if [ -n "$expected_sha256" ]; then
    if [ "${#expected_sha256}" -ne 64 ]; then
      die "Expected SHA-256 must contain exactly 64 hexadecimal characters."
    fi
    case "$expected_sha256" in
      *[!0-9A-Fa-f]*) die "Expected SHA-256 contains non-hexadecimal characters." ;;
    esac
    expected_sha256=$(printf '%s' "$expected_sha256" | tr '[:upper:]' '[:lower:]')
    actual=$(sha256_file "$archive")
    [ "$actual" = "$expected_sha256" ] || die "SHA-256 mismatch for $archive"
    log "Archive SHA-256 verified."
    return
  fi

  require_command gpg
  keyring_dir="${archive}.gnupg"
  mkdir -m 700 "$keyring_dir"
  chmod 700 "$keyring_dir"

  gpg --batch --homedir "$keyring_dir" --keyserver "$SONAR_SOURCE_KEYSERVER" \
    --recv-keys "$SONAR_SOURCE_KEY" >/dev/null 2>&1 || \
    die "Could not retrieve the pinned SonarSource signing key. Use --sha256 with a trusted checksum."

  fingerprint=$(gpg --batch --homedir "$keyring_dir" --with-colons --fingerprint "$SONAR_SOURCE_KEY" |
    awk -F: '$1 == "fpr" { print $10; exit }')
  [ "$fingerprint" = "$SONAR_SOURCE_KEY" ] || die "Unexpected SonarSource signing-key fingerprint."
  gpg --batch --homedir "$keyring_dir" --verify "$signature" "$archive" >/dev/null 2>&1 || \
    die "SonarQube archive signature verification failed."
  log "Archive signature verified with SonarSource key $SONAR_SOURCE_KEY."

  rm -rf "$keyring_dir"
}

download_and_verify() {
  version=$1
  work_dir=$2
  expected_sha256=${3:-}
  base_url="https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${version}.zip"
  archive="$work_dir/sonarqube-${version}.zip"
  signature="$archive.asc"

  log "Downloading SonarQube $version from SonarSource."
  download_file "$base_url" "$archive"
  if [ -n "$expected_sha256" ]; then
    verify_archive "$archive" "$signature" "$expected_sha256"
  else
    download_file "$base_url.asc" "$signature"
    verify_archive "$archive" "$signature" ""
  fi
  printf '%s\n' "$archive"
}

write_sonar_properties() {
  file=$1
  data_dir=$2
  logs_dir=$3
  temp_dir=$4
  jdbc_url=${5:-}
  jdbc_user=${6:-}

  {
    printf '%s\n' '# Managed by SonarWeaver.'
    printf 'sonar.path.data=%s\n' "$data_dir"
    printf 'sonar.path.logs=%s\n' "$logs_dir"
    printf 'sonar.path.temp=%s\n' "$temp_dir"
    printf '%s\n' 'sonar.web.host=127.0.0.1'
    printf '%s\n' 'sonar.web.port=9000'
    if [ -n "$jdbc_url" ]; then
      printf 'sonar.jdbc.url=%s\n' "$jdbc_url"
      printf 'sonar.jdbc.username=%s\n' "$jdbc_user"
    fi
  } >"$file"
  chmod 600 "$file"
}
