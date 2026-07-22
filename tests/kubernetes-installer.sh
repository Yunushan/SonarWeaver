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

if [ "${1:-}" = -n ]; then
  shift 2
fi

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
      storageclass|ingressclass|namespace|secret)
        exit 0
        ;;
      *)
        printf 'Unexpected kubectl get arguments: %s\n' "$*" >&2
        exit 1
        ;;
    esac
    ;;
  create)
    printf '%s\n' 'apiVersion: v1' 'kind: ConfigMap' 'metadata:' '  name: mocked'
    ;;
  apply)
    cat >>"$SONARWEAVER_KUBECTL_APPLY_LOG"
    ;;
  label)
    printf '%s\n' "$*" >>"$SONARWEAVER_KUBECTL_LABEL_LOG"
    exit 0
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
KUBECTL_APPLY_LOG="$TEST_ROOT/kubectl-apply.log"
KUBECTL_LABEL_LOG="$TEST_ROOT/kubectl-label.log"

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
    --monitoring-namespace monitoring \
    --storage-class fast-rwo \
    --database-egress-cidr 2001:db8::10/128 \
    --node-prerequisites-ready \
    --dry-run >/dev/null

grep -q '^jdbcOverwrite\.jdbcUrl=.*jdbc-url$' "$HELM_LOG"
grep -q '^jdbcOverwrite\.jdbcUsername=.*jdbc-user$' "$HELM_LOG"
if grep -q 'jdbc:postgresql' "$HELM_LOG"; then
  printf '%s\n' 'The JDBC URL leaked into Helm command arguments.' >&2
  exit 1
fi

rendered_policy=$(sed \
  -e 's|@RELEASE@|sonarqube|g' \
  -e 's|@DATABASE_EGRESS_CIDR@|10.42.0.10/32|g' \
  -e 's|port: 0 # @DATABASE_PORT@|port: 5432|g' \
  "$ROOT/deployments/kubernetes/common/network-policy.yaml.in")
printf '%s\n' "$rendered_policy" | grep -q 'name: sonarweaver-default-deny'
printf '%s\n' "$rendered_policy" | grep -q 'cidr: "10.42.0.10/32"'
printf '%s\n' "$rendered_policy" | grep -q 'sonarweaver.io/network-access: ingress'

: >"$KUBECTL_APPLY_LOG"
: >"$KUBECTL_LABEL_LOG"
PATH="$TEST_ROOT/bin:$PATH" \
  KUBE_MINOR=35 \
  SONARWEAVER_HELM_LOG="$HELM_LOG" \
  SONARWEAVER_KUBECTL_APPLY_LOG="$KUBECTL_APPLY_LOG" \
  SONARWEAVER_KUBECTL_LABEL_LOG="$KUBECTL_LABEL_LOG" \
  "$INSTALLER" \
    --distribution k3s \
    --profile production \
    --jdbc-url 'jdbc:postgresql://db.example:5432/sonarqube' \
    --jdbc-user sonarqube \
    --jdbc-password-file "$TEST_ROOT/jdbc-password" \
    --monitoring-passcode-file "$TEST_ROOT/monitoring-passcode" \
    --monitoring-namespace monitoring \
    --storage-class fast-rwo \
    --database-egress-cidr 10.42.0.10/32 \
    --database-port 15432 \
    --hostname sonar.example \
    --ingress-class nginx \
    --ingress-namespace ingress-nginx \
    --tls-secret sonar-tls \
    --node-prerequisites-ready >/dev/null

grep -q 'name: sonarweaver-default-deny' "$KUBECTL_APPLY_LOG"
grep -q 'name: sonarweaver-sonarqube' "$KUBECTL_APPLY_LOG"
grep -q 'cidr: "10.42.0.10/32"' "$KUBECTL_APPLY_LOG"
grep -q 'port: 15432' "$KUBECTL_APPLY_LOG"
grep -qx 'label namespace monitoring sonarweaver.io/network-access=monitoring --overwrite' "$KUBECTL_LABEL_LOG"
grep -qx -- '--atomic' "$HELM_LOG"

if PATH="$TEST_ROOT/bin:$PATH" \
  KUBE_MINOR=35 \
  SONARWEAVER_HELM_LOG="$HELM_LOG" \
  "$INSTALLER" \
    --distribution k3s \
    --profile production \
    --jdbc-url 'jdbc:postgresql://db.example:5432/sonarqube' \
    --jdbc-user sonarqube \
    --jdbc-password-file "$TEST_ROOT/jdbc-password" \
    --monitoring-passcode-file "$TEST_ROOT/monitoring-passcode" \
    --monitoring-namespace monitoring \
    --storage-class fast-rwo \
    --node-prerequisites-ready \
    --dry-run >/dev/null 2>&1; then
  printf '%s\n' 'Production unexpectedly accepted a missing database egress CIDR.' >&2
  exit 1
fi

if PATH="$TEST_ROOT/bin:$PATH" \
  KUBE_MINOR=35 \
  SONARWEAVER_HELM_LOG="$HELM_LOG" \
  "$INSTALLER" \
    --distribution k3s \
    --profile production \
    --jdbc-url 'jdbc:postgresql://db.example:5432/sonarqube' \
    --jdbc-user sonarqube \
    --jdbc-password-file "$TEST_ROOT/jdbc-password" \
    --monitoring-passcode-file "$TEST_ROOT/monitoring-passcode" \
    --monitoring-namespace monitoring \
    --storage-class fast-rwo \
    --database-egress-cidr 999.42.0.10/32 \
    --node-prerequisites-ready \
    --dry-run >/dev/null 2>&1; then
  printf '%s\n' 'Production unexpectedly accepted an invalid IPv4 database egress CIDR.' >&2
  exit 1
fi

if PATH="$TEST_ROOT/bin:$PATH" \
  KUBE_MINOR=35 \
  SONARWEAVER_HELM_LOG="$HELM_LOG" \
  "$INSTALLER" \
    --distribution k3s \
    --profile production \
    --jdbc-url 'jdbc:postgresql://db.example:5432/sonarqube' \
    --jdbc-user sonarqube \
    --jdbc-password-file "$TEST_ROOT/jdbc-password" \
    --monitoring-passcode-file "$TEST_ROOT/monitoring-passcode" \
    --storage-class fast-rwo \
    --database-egress-cidr 10.42.0.10/32 \
    --node-prerequisites-ready \
    --dry-run >/dev/null 2>&1; then
  printf '%s\n' 'Production unexpectedly accepted a missing monitoring namespace.' >&2
  exit 1
fi

printf '%s\n' 'Kubernetes installer tests passed.'
