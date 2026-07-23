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
DATABASE_EGRESS_CIDR=
DATABASE_PORT=5432
HOSTNAME=
INGRESS_CLASS=
INGRESS_NAMESPACE=
MONITORING_NAMESPACE=
TLS_SECRET=
CERT_MANAGER_CLUSTER_ISSUER=
NODE_PREREQUISITES_READY=false
ALLOW_UNSUPPORTED_KUBERNETES=false
DRY_RUN=false
UPGRADE_APPROVED=false
BACKUP_VERIFIED=false

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
validate_cidr() {
  value=$1
  address=${value%/*}
  prefix=${value##*/}
  [ "$address" != "$value" ] || return 1
  case "$address" in */*) return 1 ;; esac
  case "$prefix" in ''|*[!0-9]*) return 1 ;; esac

  case "$address" in
    *.*)
      [ "$prefix" -le 32 ] 2>/dev/null || return 1
      old_ifs=$IFS
      IFS=.
      # shellcheck disable=SC2086 # Deliberate split on the temporary dot-only IFS.
      set -- $address
      IFS=$old_ifs
      [ "$#" -eq 4 ] || return 1
      for octet in "$@"; do
        case "$octet" in ''|*[!0-9]*) return 1 ;; esac
        [ "$octet" -le 255 ] 2>/dev/null || return 1
      done
      return 0
      ;;
    *:*)
      case "$address" in
        :[!:]*) return 1 ;;
        *[!:]:) return 1 ;;
        :|*[!0-9A-Fa-f:]*) return 1 ;;
      esac
      [ "$prefix" -le 128 ] 2>/dev/null || return 1
      compressed=false
      case "$address" in
        *::*)
          compressed=true
          suffix=${address#*::}
          case "$suffix" in *::*) return 1 ;; esac
          ;;
      esac
      old_ifs=$IFS
      IFS=:
      # shellcheck disable=SC2086 # Deliberate split on the temporary colon-only IFS.
      set -- $address
      IFS=$old_ifs
      if [ "$compressed" = true ]; then
        [ "$#" -le 7 ] || return 1
      else
        [ "$#" -eq 8 ] || return 1
      fi
      for hextet in "$@"; do
        if [ -z "$hextet" ]; then
          [ "$compressed" = true ] || return 1
          continue
        fi
        case "$hextet" in ''|*[!0-9A-Fa-f]*) return 1 ;; esac
        [ "${#hextet}" -le 4 ] || return 1
      done
      return 0
      ;;
    *) return 1 ;;
  esac
}
validate_port() {
  value=$1
  case "$value" in ''|*[!0-9]*) return 1 ;; esac
  [ "$value" -ge 1 ] 2>/dev/null && [ "$value" -le 65535 ] 2>/dev/null
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
  --database-egress-cidr CIDR
  --node-prerequisites-ready

Options:
  --profile production|evaluation   Default: production
  --edition community|developer|enterprise
  --namespace NAME                  Default: sonarqube
  --release NAME                    Default: sonarqube
  --chart-version VERSION           Default: locked official chart
  --community-version VERSION       Exact Community Build number
  --hostname HOST                   Enable ingress
  --ingress-class NAME              Existing IngressClass; required with --hostname
  --ingress-namespace NAME          Ingress controller namespace; required with --hostname in production
  --monitoring-namespace NAME       Prometheus namespace; required in production
  --tls-secret NAME                 Existing TLS secret; required with --hostname in production
  --cert-manager-cluster-issuer NAME
                                    Existing cert-manager ClusterIssuer to obtain the
                                    --tls-secret certificate (for example, Let's Encrypt)
  --database-egress-cidr CIDR       Production IPv4 or IPv6 database network CIDR
  --database-port PORT              Production database TCP port (default: 5432)
  --allow-unsupported-kubernetes    Bypass the chart's Kubernetes 1.32-1.35 gate
  --upgrade-approved                Acknowledge the approved production upgrade plan
  --backup-verified                 Acknowledge the isolated restore verification
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
    --database-egress-cidr) need_value "$@"; DATABASE_EGRESS_CIDR=$2; shift 2 ;;
    --database-port) need_value "$@"; DATABASE_PORT=$2; shift 2 ;;
    --hostname) need_value "$@"; HOSTNAME=$2; shift 2 ;;
    --ingress-class) need_value "$@"; INGRESS_CLASS=$2; shift 2 ;;
    --ingress-namespace) need_value "$@"; INGRESS_NAMESPACE=$2; shift 2 ;;
    --monitoring-namespace) need_value "$@"; MONITORING_NAMESPACE=$2; shift 2 ;;
    --tls-secret) need_value "$@"; TLS_SECRET=$2; shift 2 ;;
    --cert-manager-cluster-issuer) need_value "$@"; CERT_MANAGER_CLUSTER_ISSUER=$2; shift 2 ;;
    --node-prerequisites-ready) NODE_PREREQUISITES_READY=true; shift ;;
    --allow-unsupported-kubernetes) ALLOW_UNSUPPORTED_KUBERNETES=true; shift ;;
    --upgrade-approved) UPGRADE_APPROVED=true; shift ;;
    --backup-verified) BACKUP_VERIFIED=true; shift ;;
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
if [ -n "$CERT_MANAGER_CLUSTER_ISSUER" ]; then
  validate_dns_label "$CERT_MANAGER_CLUSTER_ISSUER" 63 || \
    die "--cert-manager-cluster-issuer must be a lowercase DNS label of at most 63 characters."
fi
if [ -n "$INGRESS_NAMESPACE" ]; then
  validate_dns_label "$INGRESS_NAMESPACE" 63 || die "--ingress-namespace must be a lowercase DNS label of at most 63 characters."
fi
if [ -n "$MONITORING_NAMESPACE" ]; then
  validate_dns_label "$MONITORING_NAMESPACE" 63 || die "--monitoring-namespace must be a lowercase DNS label of at most 63 characters."
fi
validate_port "$DATABASE_PORT" || die "--database-port must be an integer between 1 and 65535."

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

if [ -n "$HOSTNAME" ]; then
  [ -n "$INGRESS_CLASS" ] || die "--hostname requires --ingress-class."
  validate_dns_name "$INGRESS_CLASS" || die "--ingress-class must be a lowercase Kubernetes resource name."
fi
if [ -n "$CERT_MANAGER_CLUSTER_ISSUER" ]; then
  [ -n "$HOSTNAME" ] || die "--cert-manager-cluster-issuer requires --hostname."
  [ "$PROFILE" = production ] || die "--cert-manager-cluster-issuer is available only in production mode."
fi

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
  validate_cidr "$DATABASE_EGRESS_CIDR" || die "Production requires --database-egress-cidr in CIDR form."
  [ -n "$MONITORING_NAMESPACE" ] || die "Production requires --monitoring-namespace."
  [ "$NODE_PREREQUISITES_READY" = true ] || die "Run node-prerequisites.sh on every eligible node, then pass --node-prerequisites-ready."
  kubectl get storageclass "$STORAGE_CLASS" >/dev/null 2>&1 || \
    die "StorageClass $STORAGE_CLASS was not found in the current cluster."
  kubectl get namespace "$MONITORING_NAMESPACE" >/dev/null 2>&1 || \
    die "Monitoring namespace $MONITORING_NAMESPACE was not found in the current cluster."
  if [ -n "$HOSTNAME" ]; then
    [ -n "$TLS_SECRET" ] || die "Production ingress requires --tls-secret."
    [ -n "$INGRESS_NAMESPACE" ] || die "Production ingress requires --ingress-namespace."
    if [ -n "$CERT_MANAGER_CLUSTER_ISSUER" ]; then
      kubectl get clusterissuer "$CERT_MANAGER_CLUSTER_ISSUER" >/dev/null 2>&1 || \
        die "cert-manager ClusterIssuer $CERT_MANAGER_CLUSTER_ISSUER was not found in the current cluster."
    fi
  fi
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

if [ "$PROFILE" = production ] && [ "$DRY_RUN" = false ]; then
  if ! existing_releases=$(helm list --namespace "$NAMESPACE" --filter "^$RELEASE$" --output json); then
    die "Could not inspect existing Helm releases; resolve cluster access before changing production resources."
  fi
  if printf '%s' "$existing_releases" | grep -q '"name"'; then
    if [ "$UPGRADE_APPROVED" != true ] || [ "$BACKUP_VERIFIED" != true ]; then
      die "The Helm release already exists. Complete the approved upgrade runbook and isolated restore verification, then re-run with --upgrade-approved --backup-verified."
    fi
  fi
fi

if [ -n "$HOSTNAME" ]; then
  kubectl get ingressclass "$INGRESS_CLASS" >/dev/null 2>&1 || \
    die "IngressClass $INGRESS_CLASS was not found in the current cluster."
fi

helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube --force-update >/dev/null
helm repo update >/dev/null

common_values="$PROJECT_ROOT/deployments/kubernetes/common/values.yaml"
distro_values="$PROJECT_ROOT/deployments/kubernetes/$DISTRIBUTION/values.yaml"
network_policy_template="$PROJECT_ROOT/deployments/kubernetes/common/network-policy.yaml.in"

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
  if [ -n "$CERT_MANAGER_CLUSTER_ISSUER" ]; then
    set -- "$@" \
      --set-string "ingress.annotations.cert-manager\\.io/cluster-issuer=$CERT_MANAGER_CLUSTER_ISSUER"
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
  kubectl label namespace "$MONITORING_NAMESPACE" sonarweaver.io/network-access=monitoring --overwrite >/dev/null
  kubectl -n "$NAMESPACE" create secret generic sonarqube-jdbc \
    --from-file="password=$JDBC_PASSWORD_FILE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  if [ -n "$HOSTNAME" ]; then
    kubectl get namespace "$INGRESS_NAMESPACE" >/dev/null 2>&1 || \
      die "Ingress namespace $INGRESS_NAMESPACE was not found in the current cluster."
    if [ -z "$CERT_MANAGER_CLUSTER_ISSUER" ]; then
      kubectl -n "$NAMESPACE" get secret "$TLS_SECRET" >/dev/null 2>&1 || \
        die "TLS secret $TLS_SECRET was not found in namespace $NAMESPACE."
    fi
    kubectl label namespace "$INGRESS_NAMESPACE" sonarweaver.io/network-access=ingress --overwrite >/dev/null
  fi
  [ -f "$network_policy_template" ] || die "NetworkPolicy template is missing: $network_policy_template"
  sed \
    -e "s|@RELEASE@|$RELEASE|g" \
    -e "s|@DATABASE_EGRESS_CIDR@|$DATABASE_EGRESS_CIDR|g" \
    -e "s|port: 0 # @DATABASE_PORT@|port: $DATABASE_PORT|g" \
    "$network_policy_template" | kubectl -n "$NAMESPACE" apply -f - >/dev/null
fi
kubectl -n "$NAMESPACE" create secret generic sonarqube-monitoring \
  --from-file="passcode=$MONITORING_PASSCODE_FILE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

set -- "$@" --atomic --wait
helm "$@"

log "SonarQube release $RELEASE is ready in namespace $NAMESPACE."
if [ -n "$HOSTNAME" ]; then
  if [ "$PROFILE" = production ]; then
    log "Open https://$HOSTNAME and immediately change admin/admin."
  else
    log "Open https://$HOSTNAME (or http://$HOSTNAME without TLS) and immediately change admin/admin."
  fi
else
  log "Access locally with: kubectl -n $NAMESPACE port-forward svc/$RELEASE-sonarqube 9000:9000"
fi
