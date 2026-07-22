#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sonarweaver-docker-bootstrap.XXXXXX")
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT HUP INT TERM

mkdir "$TEST_ROOT/bin" "$TEST_ROOT/docker"
cp "$ROOT/deployments/docker/bootstrap.sh" "$TEST_ROOT/docker/bootstrap.sh"
cp "$ROOT/deployments/docker/.env.example" "$TEST_ROOT/docker/.env.example"
cp "$ROOT/deployments/docker/compose.yaml" "$TEST_ROOT/docker/compose.yaml"
chmod +x "$TEST_ROOT/docker/bootstrap.sh"

cat >"$TEST_ROOT/bin/docker" <<'EOF'
#!/usr/bin/env sh
set -eu

case "${1:-}" in
  info) exit 0 ;;
  inspect) printf '%s\n' "${SONARWEAVER_TEST_RUNNING_IMAGE:-}" ;;
  compose)
    shift
    case "${1:-}" in version) exit 0 ;; esac
    case "$*" in
      *"ps -q sonarqube"*) printf '%s' "${SONARWEAVER_TEST_RUNNING_CONTAINER:-}" ;;
      *"config --quiet"*) exit 0 ;;
      *"up -d"*) exit 0 ;;
      *) printf 'Unexpected docker compose invocation: %s\n' "$*" >&2; exit 1 ;;
    esac
    ;;
  *) printf 'Unexpected docker invocation: %s\n' "$*" >&2; exit 1 ;;
esac
EOF

cat >"$TEST_ROOT/bin/sysctl" <<'EOF'
#!/usr/bin/env sh
case "${2:-}" in vm.max_map_count) printf '%s\n' 524288 ;; fs.file-max) printf '%s\n' 131072 ;; *) exit 1 ;; esac
EOF
chmod +x "$TEST_ROOT/bin/docker" "$TEST_ROOT/bin/sysctl"

prepare_env() {
  cp "$TEST_ROOT/docker/.env.example" "$TEST_ROOT/docker/.env"
  sed -i 's|postgresql\.example\.invalid|db.example.internal|g' "$TEST_ROOT/docker/.env"
}

prepare_env
PATH="$TEST_ROOT/bin:$PATH" "$TEST_ROOT/docker/bootstrap.sh" production >/dev/null

secret_mode=$(stat -c '%a' "$TEST_ROOT/docker/secrets/jdbc_password" 2>/dev/null || stat -f '%Lp' "$TEST_ROOT/docker/secrets/jdbc_password")
[ "$secret_mode" = 600 ] || {
  printf '%s\n' 'Docker bootstrap did not enforce owner-only JDBC secret permissions.' >&2
  exit 1
}

desired_image=$(sed -n 's/^SONARQUBE_IMAGE=//p' "$TEST_ROOT/docker/.env")
SONARWEAVER_TEST_RUNNING_CONTAINER=container-id \
  SONARWEAVER_TEST_RUNNING_IMAGE="$desired_image" \
  PATH="$TEST_ROOT/bin:$PATH" "$TEST_ROOT/docker/bootstrap.sh" production >/dev/null

if SONARWEAVER_TEST_RUNNING_CONTAINER=container-id \
  SONARWEAVER_TEST_RUNNING_IMAGE='sonarqube@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  PATH="$TEST_ROOT/bin:$PATH" "$TEST_ROOT/docker/bootstrap.sh" production >/dev/null 2>&1; then
  printf '%s\n' 'Production Docker bootstrap unexpectedly accepted an unacknowledged image change.' >&2
  exit 1
fi

SONARWEAVER_TEST_RUNNING_CONTAINER=container-id \
  SONARWEAVER_TEST_RUNNING_IMAGE='sonarqube@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  PATH="$TEST_ROOT/bin:$PATH" "$TEST_ROOT/docker/bootstrap.sh" production \
    --upgrade-approved --backup-verified >/dev/null

printf '%s\n' 'Docker bootstrap upgrade-gate tests passed.'
