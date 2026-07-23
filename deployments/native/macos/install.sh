#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)
# shellcheck source=../../../config/versions.env
. "$PROJECT_ROOT/config/versions.env"
# shellcheck source=../common.sh
. "$SCRIPT_DIR/../common.sh"

VERSION=$SONARQUBE_COMMUNITY_VERSION
BASE_DIR=${HOME}/Library/Application\ Support/SonarWeaver
JDBC_URL=
JDBC_USER=
JDBC_PASSWORD_FILE=
EXPECTED_SHA256=
EVALUATION=false
NO_START=false
DRY_RUN=false
APPLY_LIMITS=false
UPGRADE_APPROVED=false
BACKUP_VERIFIED=false
LABEL=io.github.yunushan.sonarweaver

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Installs SonarQube for the current user on a supported macOS host.

Options:
  --version VERSION             Community/Server ZIP version
  --base-dir PATH               Install and state root
  --jdbc-url URL                Production JDBC URL
  --jdbc-user USER              Production database user
  --jdbc-password-file PATH     File containing the database password
  --sha256 HEX                  Trusted archive checksum; otherwise GPG is used
  --evaluation                  Use embedded H2 (evaluation only)
  --apply-limits                Apply current-session kernel file limits with sudo
  --no-start                    Install without loading the LaunchAgent
  --upgrade-approved            Acknowledge the approved production upgrade plan
  --backup-verified             Acknowledge the isolated restore verification
  --dry-run                     Validate and print the plan only
  -h, --help                    Show this help

Production mode is the default and requires all three JDBC options. macOS is
best suited to local evaluation; Linux is usually preferable for production.
EOF
}

need_value() {
  [ "$#" -ge 2 ] || die "$1 requires a value."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) need_value "$@"; VERSION=$2; shift 2 ;;
    --base-dir) need_value "$@"; BASE_DIR=$2; shift 2 ;;
    --jdbc-url) need_value "$@"; JDBC_URL=$2; shift 2 ;;
    --jdbc-user) need_value "$@"; JDBC_USER=$2; shift 2 ;;
    --jdbc-password-file) need_value "$@"; JDBC_PASSWORD_FILE=$2; shift 2 ;;
    --sha256) need_value "$@"; EXPECTED_SHA256=$2; shift 2 ;;
    --evaluation) EVALUATION=true; shift ;;
    --apply-limits) APPLY_LIMITS=true; shift ;;
    --no-start) NO_START=true; shift ;;
    --upgrade-approved) UPGRADE_APPROVED=true; shift ;;
    --backup-verified) BACKUP_VERIFIED=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[ "$(uname -s)" = Darwin ] || die "This installer supports macOS only."
case "$(uname -m)" in
  x86_64|arm64) ;;
  *) die "Unsupported macOS architecture: $(uname -m)" ;;
esac
validate_version "$VERSION"
check_java
require_command unzip

if [ "$EVALUATION" = true ]; then
  [ -z "$JDBC_URL$JDBC_USER$JDBC_PASSWORD_FILE" ] || die "Do not combine --evaluation with JDBC options."
  warn "Embedded H2 is for evaluation only and must not hold production data."
else
  [ -n "$JDBC_URL" ] || die "Production mode requires --jdbc-url."
  [ -n "$JDBC_USER" ] || die "Production mode requires --jdbc-user."
  [ -n "$JDBC_PASSWORD_FILE" ] || die "Production mode requires --jdbc-password-file."
  validate_secret_file "JDBC password file" "$JDBC_PASSWORD_FILE"
fi

maxfiles=$(sysctl -n kern.maxfiles 2>/dev/null || printf '0')
maxfilesperproc=$(sysctl -n kern.maxfilesperproc 2>/dev/null || printf '0')
if [ "$maxfiles" -lt 131072 ] 2>/dev/null || [ "$maxfilesperproc" -lt 131072 ] 2>/dev/null; then
  warn "macOS file limits are below 131072; use --apply-limits or configure them administratively."
fi

version_dir="$BASE_DIR/versions/$VERSION"
data_dir="$BASE_DIR/data"
logs_dir="$BASE_DIR/logs"
temp_dir="$BASE_DIR/temp"
config_dir="$BASE_DIR/config"
password_target="$config_dir/jdbc-password"
wrapper="$BASE_DIR/sonarweaver-start"
plist="$HOME/Library/LaunchAgents/$LABEL.plist"

log "Plan: install SonarQube $VERSION into $version_dir"
log "Plan: create LaunchAgent $LABEL"
if [ "$DRY_RUN" = true ]; then
  log "Dry run complete; no changes made."
  exit 0
fi

if [ "$EVALUATION" = false ] && { [ -L "$BASE_DIR/current" ] || [ -e "$BASE_DIR/current" ]; }; then
  if [ "$UPGRADE_APPROVED" != true ] || [ "$BACKUP_VERIFIED" != true ]; then
    die "A managed production installation already exists. Complete the approved upgrade runbook and isolated restore verification, then re-run with --upgrade-approved --backup-verified."
  fi
fi

if [ "$APPLY_LIMITS" = true ]; then
  sudo sysctl -w kern.maxfiles=131072 kern.maxfilesperproc=131072 >/dev/null
fi

umask 027
mkdir -p "$BASE_DIR/versions" "$data_dir" "$logs_dir" "$temp_dir" "$config_dir" "$HOME/Library/LaunchAgents"
chmod 700 "$config_dir"

new_install=false
if [ ! -d "$version_dir" ]; then
  new_install=true
  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/sonarweaver-install.XXXXXX")
  cleanup_work() { rm -rf "$work_dir"; }
  trap cleanup_work EXIT HUP INT TERM
  archive=$(download_and_verify "$VERSION" "$work_dir" "$EXPECTED_SHA256")
  unzip -q "$archive" -d "$work_dir/extracted"
  extracted="$work_dir/extracted/sonarqube-$VERSION"
  [ -d "$extracted" ] || die "Unexpected archive layout."
  mv "$extracted" "$version_dir"
  trap - EXIT HUP INT TERM
  cleanup_work
else
  [ -f "$version_dir/lib/sonar-application-$VERSION.jar" ] || \
    die "Existing version directory is incomplete: $version_dir"
  log "Version $VERSION is already present; reusing it."
fi

properties="$version_dir/conf/sonar.properties"
if [ "$new_install" = false ] && \
   { [ ! -f "$properties" ] || ! grep -q '^# Managed by SonarWeaver\.$' "$properties"; }; then
  die "Refusing to overwrite an unmanaged sonar.properties in an existing installation."
fi
write_sonar_properties "$properties" "$data_dir" "$logs_dir" "$temp_dir" "$JDBC_URL" "$JDBC_USER"

if [ "$EVALUATION" = false ]; then
  cp "$JDBC_PASSWORD_FILE" "$password_target"
  chmod 400 "$password_target"
else
  rm -f "$password_target"
fi

launcher="$version_dir/bin/macosx-universal-64/sonar.sh"
[ -f "$launcher" ] || die "The supported macOS sonar.sh launcher is missing from the archive."
chmod 0755 "$launcher"
ln -sfn "versions/$VERSION" "$BASE_DIR/current"
current_launcher="$BASE_DIR/current/${launcher#"$version_dir/"}"

{
  printf '%s\n' '#!/usr/bin/env sh' 'set -eu' 'ulimit -n 131072 2>/dev/null || true'
  printf 'if [ -r %s ]; then\n' "\"$password_target\""
  # The command substitution is intentionally written into the generated wrapper.
  # shellcheck disable=SC2016
  printf '  SONAR_JDBC_PASSWORD=$(cat %s)\n' "\"$password_target\""
  printf '%s\n' '  export SONAR_JDBC_PASSWORD' 'fi'
  printf 'exec %s console\n' "\"$current_launcher\""
} >"$wrapper"
chmod 700 "$wrapper"

xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}
wrapper_xml=$(xml_escape "$wrapper")
stdout_xml=$(xml_escape "$logs_dir/launchd.out.log")
stderr_xml=$(xml_escape "$logs_dir/launchd.err.log")
{
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
  printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  printf '%s\n' '<plist version="1.0"><dict>'
  printf '%s\n' '  <key>Label</key><string>io.github.yunushan.sonarweaver</string>'
  printf '  <key>ProgramArguments</key><array><string>%s</string></array>\n' "$wrapper_xml"
  printf '%s\n' '  <key>RunAtLoad</key><true/>' '  <key>KeepAlive</key><true/>'
  printf '  <key>StandardOutPath</key><string>%s</string>\n' "$stdout_xml"
  printf '  <key>StandardErrorPath</key><string>%s</string>\n' "$stderr_xml"
  printf '%s\n' '</dict></plist>'
} >"$plist"
chmod 600 "$plist"
plutil -lint "$plist" >/dev/null

if [ "$NO_START" = false ]; then
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  log "SonarQube is starting. Logs: $logs_dir"
else
  log "Installed without starting. Load with: launchctl bootstrap gui/$(id -u) '$plist'"
fi
log "After startup, open http://127.0.0.1:9000 and immediately change admin/admin."
