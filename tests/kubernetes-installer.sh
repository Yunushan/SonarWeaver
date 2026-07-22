#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sonarweaver-test.XXXXXX")
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT HUP INT TERM

mkdir "$TEST_ROOT/bin"

cat >"$TEST_ROOT/bin/kubectl" <<'EOF'
#!/usr/bin/env sh
set -eu

case "${1:-}" in
  cluster-info)
    exit 0
    ;;
  get)
    case "${2:-}" in
      --raw)
        printf '{"major":"1","minor":"%s"}\n' "${KUBE_MINOR:-35}"
        ;;
      nodes)
        printf 'v1.%s.0+k3s1' "${KUBE_MINOR:-35}"
        ;;
      storageclass|ingressclass)
        exit 0
        ;;
      *)
        printf 'Unexpected kubectl get arguments: %s\n' "$*" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    printf 'Unexpected kubectl arguments: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

cat >"$TEST_ROOT/bin/helm" <<'EOF'
#!/usr/bin/env sh
set -eu

case "${1:-}" in
  repo)
    exit 0
    ;;
  upgrade)
    printf '%s\n' "$@" >"$SONARWEAVER_HELM_LOG"
    ;;
  *)
    printf 'Unexpected Helm arguments: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$TEST_ROOT/bin/kubectl" "$TEST_ROOT/bin/helm"
INSTALLER="$ROOT/deployments/kubernetes/scripts/install.sh"
HELM_LOG="$TEST_ROOT/helm.log"

PATH="$TEST_ROOT/bin:$PATH" \
  KUBE_MINOR=35 \
  SONARWEAVER_HELM_LOG="$HELM_LOG" \
  "$INSTALLER" --distribution k3s --profile evaluation --dry-run >/dev/null

grep -qx -- '--dry-run=client' "$HELM_LOG"
grep -qx -- '2026.3.1' "$HELM_LOG"
grep -qx -- 'community.buildNumber=26.7.0.124771' "$HELM_LOG"

if PATH="$TEST_ROOT/bin:$PATH" \
  KUBE_MINOR=36 \
  SONARWEAVER_HELM_LOG="$HELM_LOG" \
  "$INSTALLER" --distribution k3s --profile evaluation --dry-run >/dev/null 2>&1; then
  printf '%s\n' 'Kubernetes 1.36 unexpectedly passed the supported-version gate.' >&2
  exit 1
fi

printf '%s' 'db-password' >"$TEST_ROOT/jdbc-password"
printf '%s' 'monitoring-passcode' >"$TEST_ROOT/monitoring-passcode"
PATH="$TEST_ROOT/bin:$PATH" \
  KUBE_MINOR=35 \
  SONARWEAVER_HELM_LOG="$HELM_LOG" \
  "$INSTALLER" \
    --distribution k3s \
    --profile production \
    --jdbc-url 'jdbc:postgresql://db.example:5432/sonarqube?options=a,b' \
    --jdbc-user sonarqube \
    --jdbc-password-file "$TEST_ROOT/jdbc-password" \
    --monitoring-passcode-file "$TEST_ROOT/monitoring-passcode" \
    --storage-class fast-rwo \
    --node-prerequisites-ready \
    --dry-run >/dev/null

grep -q '^jdbcOverwrite\.jdbcUrl=.*jdbc-url$' "$HELM_LOG"
grep -q '^jdbcOverwrite\.jdbcUsername=.*jdbc-user$' "$HELM_LOG"
if grep -q 'jdbc:postgresql' "$HELM_LOG"; then
  printf '%s\n' 'The JDBC URL leaked into Helm command arguments.' >&2
  exit 1
fi

printf '%s\n' 'Kubernetes installer tests passed.'
