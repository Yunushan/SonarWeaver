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
INSTALL_ROOT=/opt/sonarqube
DATA_DIR=/var/lib/sonarqube/data
LOGS_DIR=/var/log/sonarqube
TEMP_DIR=/var/lib/sonarqube/temp
CONFIG_DIR=/etc/sonarqube
SERVICE_USER=sonarqube
SERVICE_GROUP=sonarqube
JDBC_URL=
JDBC_USER=
JDBC_PASSWORD_FILE=
EXPECTED_SHA256=
EVALUATION=false
NO_START=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [options]

Installs a pinned SonarQube ZIP on a supported Linux host.

Options:
  --version VERSION             Community/Server ZIP version
  --install-root PATH           Versioned install root (default: /opt/sonarqube)
  --data-dir PATH               Persistent data path
  --logs-dir PATH               Persistent logs path
  --temp-dir PATH               Persistent temporary path
  --service-user USER           Dedicated service user (default: sonarqube)
  --jdbc-url URL                Production JDBC URL
  --jdbc-user USER              Production database user
  --jdbc-password-file PATH     File containing the database password
  --sha256 HEX                  Trusted archive checksum; otherwise GPG is used
  --evaluation                  Use embedded H2 (evaluation only)
  --no-start                    Install and enable without starting
  --dry-run                     Validate and print the plan only
  -h, --help                    Show this help

Production mode is the default and requires all three JDBC options.
EOF
}

need_value() {
  [ "$#" -ge 2 ] || die "$1 requires a value."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) need_value "$@"; VERSION=$2; shift 2 ;;
    --install-root) need_value "$@"; INSTALL_ROOT=$2; shift 2 ;;
    --data-dir) need_value "$@"; DATA_DIR=$2; shift 2 ;;
    --logs-dir) need_value "$@"; LOGS_DIR=$2; shift 2 ;;
    --temp-dir) need_value "$@"; TEMP_DIR=$2; shift 2 ;;
    --service-user) need_value "$@"; SERVICE_USER=$2; SERVICE_GROUP=$2; shift 2 ;;
    --jdbc-url) need_value "$@"; JDBC_URL=$2; shift 2 ;;
    --jdbc-user) need_value "$@"; JDBC_USER=$2; shift 2 ;;
    --jdbc-password-file) need_value "$@"; JDBC_PASSWORD_FILE=$2; shift 2 ;;
    --sha256) need_value "$@"; EXPECTED_SHA256=$2; shift 2 ;;
    --evaluation) EVALUATION=true; shift ;;
    --no-start) NO_START=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[ "$(uname -s)" = Linux ] || die "This installer supports Linux only."
case "$(uname -m)" in
  x86_64|amd64|aarch64|arm64) ;;
  *) die "Unsupported Linux architecture: $(uname -m)" ;;
esac
validate_version "$VERSION"
check_java
require_command unzip
require_command systemctl
[ -d /run/systemd/system ] || die "systemd is not running; this installer provides a systemd service."

if [ "$EVALUATION" = true ]; then
  [ -z "$JDBC_URL$JDBC_USER$JDBC_PASSWORD_FILE" ] || die "Do not combine --evaluation with JDBC options."
  warn "Embedded H2 is for evaluation only and must not hold production data."
else
  [ -n "$JDBC_URL" ] || die "Production mode requires --jdbc-url."
  [ -n "$JDBC_USER" ] || die "Production mode requires --jdbc-user."
  [ -n "$JDBC_PASSWORD_FILE" ] || die "Production mode requires --jdbc-password-file."
  validate_secret_file "JDBC password file" "$JDBC_PASSWORD_FILE"
fi

if [ -r /proc/meminfo ]; then
  memory_kib=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  [ "${memory_kib:-0}" -ge 3900000 ] || warn "Less than 4 GB RAM detected."
fi
cpu_count=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '0')
[ "$cpu_count" -ge 2 ] 2>/dev/null || warn "Fewer than two CPU cores detected."

version_dir="$INSTALL_ROOT/versions/$VERSION"
password_target="$CONFIG_DIR/jdbc-password"

log "Plan: install SonarQube $VERSION into $version_dir"
log "Plan: persistent data=$DATA_DIR logs=$LOGS_DIR temp=$TEMP_DIR"
if [ "$DRY_RUN" = true ]; then
  log "Dry run complete; no changes made."
  exit 0
fi

[ "$(id -u)" -eq 0 ] || die "Run this system installation as root (for example with sudo)."

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  nologin_shell=$(command -v nologin 2>/dev/null || printf '/usr/sbin/nologin')
  useradd --system --home-dir "$INSTALL_ROOT" --shell "$nologin_shell" "$SERVICE_USER"
fi
SERVICE_GROUP=$(id -gn "$SERVICE_USER")

install -d -o root -g root -m 0755 "$INSTALL_ROOT" "$INSTALL_ROOT/versions"
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0750 "$DATA_DIR" "$LOGS_DIR" "$TEMP_DIR"
install -d -o root -g "$SERVICE_GROUP" -m 0750 "$CONFIG_DIR"

sysctl_file=/etc/sysctl.d/99-sonarweaver.conf
limits_file=/etc/security/limits.d/99-sonarweaver.conf
map_count=$(sysctl -n vm.max_map_count 2>/dev/null || printf '0')
file_max=$(sysctl -n fs.file-max 2>/dev/null || printf '0')
[ "$map_count" -ge 524288 ] 2>/dev/null || map_count=524288
[ "$file_max" -ge 131072 ] 2>/dev/null || file_max=131072
{
  printf '%s\n' '# Managed by SonarWeaver.'
  printf 'vm.max_map_count=%s\n' "$map_count"
  printf 'fs.file-max=%s\n' "$file_max"
} >"$sysctl_file"
chmod 0644 "$sysctl_file"
{
  printf '%s\n' '# Managed by SonarWeaver.'
  printf '%s - nofile 131072\n' "$SERVICE_USER"
  printf '%s - nproc 8192\n' "$SERVICE_USER"
} >"$limits_file"
chmod 0644 "$limits_file"
sysctl -p "$sysctl_file" >/dev/null

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
write_sonar_properties "$properties" "$DATA_DIR" "$LOGS_DIR" "$TEMP_DIR" "$JDBC_URL" "$JDBC_USER"
chown "$SERVICE_USER:$SERVICE_GROUP" "$properties"

if [ "$EVALUATION" = false ]; then
  install -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0400 "$JDBC_PASSWORD_FILE" "$password_target"
else
  rm -f "$password_target"
fi

launcher="$version_dir/bin/linux-x86-64/sonar.sh"
[ -f "$launcher" ] || die "The supported Linux sonar.sh launcher is missing from the archive."
chmod 0755 "$launcher"
chown -R root:root "$version_dir"
chown "$SERVICE_USER:$SERVICE_GROUP" "$properties"
ln -sfn "versions/$VERSION" "$INSTALL_ROOT/current"

install -d -o root -g root -m 0755 /usr/local/libexec
sed \
  -e "s|@PASSWORD_FILE@|$password_target|g" \
  -e "s|@LAUNCHER@|$INSTALL_ROOT/current/${launcher#"$version_dir/"}|g" \
  "$SCRIPT_DIR/start-wrapper.in" >/usr/local/libexec/sonarweaver-start
chmod 0755 /usr/local/libexec/sonarweaver-start

sed \
  -e "s|@SERVICE_USER@|$SERVICE_USER|g" \
  -e "s|@SERVICE_GROUP@|$SERVICE_GROUP|g" \
  "$SCRIPT_DIR/sonarqube.service.in" >/etc/systemd/system/sonarqube.service
chmod 0644 /etc/systemd/system/sonarqube.service

systemctl daemon-reload
systemctl enable sonarqube.service >/dev/null
if [ "$NO_START" = false ]; then
  systemctl restart sonarqube.service
  log "SonarQube is starting. Follow logs with: journalctl -u sonarqube -f"
else
  log "Installed without starting. Start with: systemctl start sonarqube"
fi
log "After startup, open http://127.0.0.1:9000 and immediately change admin/admin."
