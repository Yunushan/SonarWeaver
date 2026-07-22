#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)
# shellcheck source=../../../config/versions.env
. "$PROJECT_ROOT/config/versions.env"

DISTRIBUTION=
PROFILE=production
EDITION=community
NAMESPACE=sonarqube
RELEASE=sonarqube
CHART_VERSION=$SONARQUBE_HELM_CHART_VERSION
COMMUNITY_VERSION=$SONARQUBE_COMMUNITY_VERSION
JDBC_URL=
JDBC_USER=
JDBC_PASSWORD_FILE=
MONITORING_PASSCODE_FILE=
STORAGE_CLASS=
HOSTNAME=
INGRESS_CLASS=
TLS_SECRET=
NODE_PREREQUISITES_READY=false
ALLOW_UNSUPPORTED_KUBERNETES=false
DRY_RUN=false

log() { printf '%s\n' "[sonarweaver] $*" >&2; }
die() { printf '%s\n' "[sonarweaver] ERROR: $*" >&2; exit 1; }
need_value() { [ "$#" -ge 2 ] || die "$1 requires a value."; }
validate_secret_file() {
  label=$1
  file=$2
  if [ ! -r "$file" ] || [ ! -s "$file" ]; then
    die "$label must be a readable, non-empty file."
  fi
  file_size=$(wc -c <"$file" | awk '{print $1}')
  flat_size=$(tr -d '\015\012' <"$file" | wc -c | awk '{print $1}')
  [ "$file_size" = "$flat_size" ] || \
    die "$label must not contain a trailing newline; create it with printf, not echo."
}
validate_dns_label() {
  value=$1
  max_length=$2
  case "$value" in
    ''|*[!a-z0-9-]*|-*|*-) return 1 ;;
  esac
  [ "${#value}" -le "$max_length" ]
}
validate_dns_name() {
  value=$1
  case "$value" in
    ''|*[!a-z0-9.-]*|.*|*.|-*|*-) return 1 ;;
  esac
  [ "${#value}" -le 253 ]
}

usage() {
  cat <<'EOF'
Usage: ./install.sh --distribution rke2|k3s [options]

Required for production:
  --jdbc-url URL
  --jdbc-user USER
  --jdbc-password-file PATH
  --monitoring-passcode-file PATH
  --storage-class NAME
  --node-prerequisites-ready

Options:
  --profile production|evaluation   Default: production
  --edition community|developer|enterprise
  --namespace NAME                  Default: sonarqube
  --release NAME                    Default: sonarqube
  --chart-version VERSION           Default: locked official chart
  --community-version VERSION       Exact Community Build number
  --hostname HOST                   Enable ingress
  --ingress-class NAME              Defaults to nginx (RKE2) or traefik (K3s)
  --tls-secret NAME                 Existing TLS secret for the hostname
  --allow-unsupported-kubernetes    Bypass the chart's Kubernetes 1.32-1.35 gate
  --dry-run                         Render manifests without applying them
  -h, --help                        Show this help

Evaluation mode uses embedded H2, disables persistence, and is never suitable
for production data. The installer operates on the current kubeconfig context.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --distribution) need_value "$@"; DISTRIBUTION=$2; shift 2 ;;
    --profile) need_value "$@"; PROFILE=$2; shift 2 ;;
    --edition) need_value "$@"; EDITION=$2; shift 2 ;;
    --namespace) need_value "$@"; NAMESPACE=$2; shift 2 ;;
    --release) need_value "$@"; RELEASE=$2; shift 2 ;;
    --chart-version) need_value "$@"; CHART_VERSION=$2; shift 2 ;;
    --community-version) need_value "$@"; COMMUNITY_VERSION=$2; shift 2 ;;
    --jdbc-url) need_value "$@"; JDBC_URL=$2; shift 2 ;;
    --jdbc-user) need_value "$@"; JDBC_USER=$2; shift 2 ;;
    --jdbc-password-file) need_value "$@"; JDBC_PASSWORD_FILE=$2; shift 2 ;;
    --monitoring-passcode-file) need_value "$@"; MONITORING_PASSCODE_FILE=$2; shift 2 ;;
    --storage-class) need_value "$@"; STORAGE_CLASS=$2; shift 2 ;;
    --hostname) need_value "$@"; HOSTNAME=$2; shift 2 ;;
    --ingress-class) need_value "$@"; INGRESS_CLASS=$2; shift 2 ;;
    --tls-secret) need_value "$@"; TLS_SECRET=$2; shift 2 ;;
    --node-prerequisites-ready) NODE_PREREQUISITES_READY=true; shift ;;
    --allow-unsupported-kubernetes) ALLOW_UNSUPPORTED_KUBERNETES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

case "$DISTRIBUTION" in rke2|k3s) ;; *) die "Use --distribution rke2 or k3s." ;; esac
case "$PROFILE" in production|evaluation) ;; *) die "Invalid profile: $PROFILE" ;; esac
case "$EDITION" in community|developer|enterprise) ;; *) die "Invalid edition: $EDITION" ;; esac
case "$CHART_VERSION$COMMUNITY_VERSION" in
  *[!0-9A-Za-z._-]*) die "A version contains unsafe characters." ;;
esac
validate_dns_label "$NAMESPACE" 63 || die "--namespace must be a lowercase DNS label of at most 63 characters."
validate_dns_label "$RELEASE" 53 || die "--release must be a lowercase Helm release name of at most 53 characters."
if [ -n "$STORAGE_CLASS" ]; then
  validate_dns_name "$STORAGE_CLASS" || die "--storage-class must be a lowercase Kubernetes resource name."
fi
if [ -n "$HOSTNAME" ]; then
  validate_dns_name "$HOSTNAME" || die "--hostname must be a lowercase DNS name."
fi
if [ -n "$TLS_SECRET" ]; then
  validate_dns_name "$TLS_SECRET" || die "--tls-secret must be a lowercase Kubernetes resource name."
fi

command -v kubectl >/dev/null 2>&1 || die "kubectl is required."
command -v helm >/dev/null 2>&1 || die "Helm 3 is required."
kubectl cluster-info >/dev/null 2>&1 || die "The current Kubernetes context is not reachable."

version_json=$(kubectl get --raw /version | tr -d ' \n\r\t')
kube_major=$(printf '%s' "$version_json" | sed -n 's/.*"major":"\([0-9][0-9]*\)".*/\1/p')
kube_minor=$(printf '%s' "$version_json" | sed -n 's/.*"minor":"\([0-9][0-9]*\)[^\"]*".*/\1/p')
if [ -z "$kube_major" ] || [ -z "$kube_minor" ]; then
  die "Could not determine Kubernetes server version."
fi
if [ "$kube_major" -ne 1 ] || [ "$kube_minor" -lt "$KUBERNETES_MIN_MINOR" ] || [ "$kube_minor" -gt "$KUBERNETES_MAX_MINOR" ]; then
  if [ "$ALLOW_UNSUPPORTED_KUBERNETES" = false ]; then
    die "Official chart $CHART_VERSION supports Kubernetes 1.$KUBERNETES_MIN_MINOR-1.$KUBERNETES_MAX_MINOR; current server is $kube_major.$kube_minor."
  fi
  log "WARNING: Kubernetes $kube_major.$kube_minor is outside the validated chart range."
else
  log "Kubernetes server $kube_major.$kube_minor is within the selected policy."
fi

detected_version=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null || true)
case "$detected_version" in
  *k3s*) [ "$DISTRIBUTION" = k3s ] || die "Current context looks like K3s, not RKE2." ;;
  *rke2*) [ "$DISTRIBUTION" = rke2 ] || die "Current context looks like RKE2, not K3s." ;;
  *) log "Could not confirm distribution from kubelet version: ${detected_version:-unknown}" ;;
esac

if [ -z "$INGRESS_CLASS" ]; then
  if [ "$DISTRIBUTION" = rke2 ]; then INGRESS_CLASS=nginx; else INGRESS_CLASS=traefik; fi
fi
validate_dns_name "$INGRESS_CLASS" || die "--ingress-class must be a lowercase Kubernetes resource name."

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/sonarweaver-helm.XXXXXX")
cleanup() { rm -rf "$temp_dir"; }
trap cleanup EXIT HUP INT TERM

if [ "$PROFILE" = production ]; then
  [ -n "$JDBC_URL" ] || die "Production requires --jdbc-url."
  case "$JDBC_URL" in jdbc:*) ;; *) die "--jdbc-url must begin with jdbc:." ;; esac
  [ -n "$JDBC_USER" ] || die "Production requires --jdbc-user."
  validate_secret_file "--jdbc-password-file" "$JDBC_PASSWORD_FILE"
  validate_secret_file "--monitoring-passcode-file" "$MONITORING_PASSCODE_FILE"
  [ -n "$STORAGE_CLASS" ] || die "Production requires an explicit durable --storage-class."
  [ "$NODE_PREREQUISITES_READY" = true ] || die "Run node-prerequisites.sh on every eligible node, then pass --node-prerequisites-ready."
  kubectl get storageclass "$STORAGE_CLASS" >/dev/null 2>&1 || \
    die "StorageClass $STORAGE_CLASS was not found in the current cluster."
else
  [ -z "$JDBC_URL$JDBC_USER$JDBC_PASSWORD_FILE$STORAGE_CLASS" ] || die "Evaluation mode does not accept JDBC or storage options."
  if [ -z "$MONITORING_PASSCODE_FILE" ]; then
    MONITORING_PASSCODE_FILE="$temp_dir/monitoring-passcode"
    if command -v openssl >/dev/null 2>&1; then
      openssl rand -hex 32 | tr -d '\015\012' >"$MONITORING_PASSCODE_FILE"
    else
      od -An -N32 -tx1 /dev/urandom | tr -d ' \n' >"$MONITORING_PASSCODE_FILE"
    fi
    chmod 600 "$MONITORING_PASSCODE_FILE"
  else
    validate_secret_file "--monitoring-passcode-file" "$MONITORING_PASSCODE_FILE"
  fi
  log "Evaluation mode selected: embedded H2 and no persistence."
fi

if [ -n "$HOSTNAME" ]; then
  kubectl get ingressclass "$INGRESS_CLASS" >/dev/null 2>&1 || \
    die "IngressClass $INGRESS_CLASS was not found in the current cluster."
fi

helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube --force-update >/dev/null
helm repo update >/dev/null

common_values="$PROJECT_ROOT/deployments/kubernetes/common/values.yaml"
distro_values="$PROJECT_ROOT/deployments/kubernetes/$DISTRIBUTION/values.yaml"

set -- upgrade --install "$RELEASE" sonarqube/sonarqube \
  --namespace "$NAMESPACE" --create-namespace \
  --version "$CHART_VERSION" \
  --values "$common_values" --values "$distro_values" \
  --history-max 10 --timeout 20m

if [ "$EDITION" = community ]; then
  set -- "$@" \
    --set community.enabled=true \
    --set-string "community.buildNumber=$COMMUNITY_VERSION"
else
  set -- "$@" \
    --set community.enabled=false \
    --set-string "edition=$EDITION"
fi

if [ "$PROFILE" = production ]; then
  printf '%s' "$JDBC_URL" >"$temp_dir/jdbc-url"
  printf '%s' "$JDBC_USER" >"$temp_dir/jdbc-user"
  set -- "$@" \
    --set jdbcOverwrite.enabled=true \
    --set-file "jdbcOverwrite.jdbcUrl=$temp_dir/jdbc-url" \
    --set-file "jdbcOverwrite.jdbcUsername=$temp_dir/jdbc-user" \
    --set-string "persistence.storageClass=$STORAGE_CLASS" \
    --set initSysctl.enabled=false --set initFs.enabled=false
else
  set -- "$@" \
    --set jdbcOverwrite.enabled=false \
    --set persistence.enabled=false \
    --set initSysctl.enabled=true --set initFs.enabled=true
fi

if [ -n "$HOSTNAME" ]; then
  set -- "$@" \
    --set ingress.enabled=true \
    --set-string "ingress.ingressClassName=$INGRESS_CLASS" \
    --set-string "ingress.hosts[0].name=$HOSTNAME" \
    --set-string 'ingress.hosts[0].path=/' \
    --set-string 'ingress.hosts[0].pathType=Prefix'
  if [ -n "$TLS_SECRET" ]; then
    set -- "$@" \
      --set-string "ingress.tls[0].secretName=$TLS_SECRET" \
      --set-string "ingress.tls[0].hosts[0]=$HOSTNAME"
  fi
fi

if [ "$DRY_RUN" = true ]; then
  set -- "$@" --dry-run=client --hide-secret
  helm "$@" >/dev/null || die "Helm dry-run validation failed."
  log "Dry run rendered successfully; no cluster resources changed."
  exit 0
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if [ "$PROFILE" = production ]; then
  kubectl label namespace "$NAMESPACE" \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/warn=restricted --overwrite >/dev/null
  kubectl -n "$NAMESPACE" create secret generic sonarqube-jdbc \
    --from-file="password=$JDBC_PASSWORD_FILE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
fi
kubectl -n "$NAMESPACE" create secret generic sonarqube-monitoring \
  --from-file="passcode=$MONITORING_PASSCODE_FILE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

set -- "$@" --atomic --wait
helm "$@"

log "SonarQube release $RELEASE is ready in namespace $NAMESPACE."
if [ -n "$HOSTNAME" ]; then
  log "Open https://$HOSTNAME (or http://$HOSTNAME without TLS) and immediately change admin/admin."
else
  log "Access locally with: kubectl -n $NAMESPACE port-forward svc/$RELEASE-sonarqube 9000:9000"
fi
