#!/usr/bin/env python3
"""Static invariants for SonarWeaver's delivery workflow."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
versions = (ROOT / "config" / "versions.env").read_text(encoding="utf-8")
ci_requirements = (ROOT / "requirements-ci.txt").read_text(encoding="utf-8")

failures: list[str] = []
if "runs-on: ubuntu-latest" in workflow:
    failures.append("Linux CI must pin ubuntu-24.04 instead of ubuntu-latest.")
if "schedule:\n    - cron:" not in workflow:
    failures.append("CI must run on a schedule so pinned-image vulnerabilities are re-evaluated.")
if "run: .\\tests\\windows-installer-policy.ps1" not in workflow:
    failures.append("CI must run the Windows installer security-invariant test.")
if "run: .\\tests\\verify-production.ps1" not in workflow:
    failures.append("CI must run the Windows production verifier contract test.")
if "apply --dry-run=server -f -" not in workflow:
    failures.append("CI must validate the rendered production NetworkPolicy with a Kubernetes API.")
if "kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f" not in workflow:
    failures.append("CI must pin the Kind Kubernetes node image by immutable digest.")
if "pip install -r requirements-ci.txt" not in workflow:
    failures.append("CI must install its Python tooling from the reviewed requirements lock.")
if "upload-artifact-retention: 90" not in workflow:
    failures.append("CI must retain generated SBOM artifacts for 90 days rather than relying on repository defaults.")
if "trivyignores: .trivyignore.yaml" not in workflow:
    failures.append("Trivy must use the reviewed, path-scoped exception file.")
if "grep -Eq '^kind: (Deployment|StatefulSet)$'" not in workflow or "grep -q '^kind: Service$'" not in workflow:
    failures.append("Helm CI must verify that the pinned chart renders its workload and service resources.")
if (
    "selector='app=sonarqube,release=sonarqube'" not in workflow
    or "get statefulset -l" not in workflow
    or 'rollout status "${workload}"' not in workflow
):
    failures.append("Kubernetes integration must discover the chart workload and service through documented release labels.")
if "working-directory: ansible\n        run: ansible-lint ." not in workflow:
    failures.append("Ansible lint must run from the Ansible project directory so its role path and lint configuration apply.")
if "ANSIBLE_CONFIG: ${{ github.workspace }}/ansible/ansible.cfg" not in workflow:
    failures.append("Ansible CI must explicitly select its checked-in configuration for deterministic role discovery.")
for required in (
    "sonarweaver_recovery_probe",
    "pg_dump --format=custom",
    "pg_restore --exit-on-error --no-owner",
):
    if required not in workflow:
        failures.append(f"CI must prove a PostgreSQL backup restores known data: {required}")

for requirement in (
    "ansible-core==2.21.2",
    "ansible-lint==26.6.0",
    "molecule==26.6.0",
    "zizmor==1.28.0",
):
    if requirement not in ci_requirements:
        failures.append(f"CI requirement must remain exactly pinned: {requirement}")

for action, reference in re.findall(r"^\s*uses:\s*([^@\s]+)@([^\s#]+)", workflow, re.MULTILINE):
    if not re.fullmatch(r"[0-9a-f]{40}", reference):
        failures.append(f"Action {action} is not pinned to a 40-character commit SHA.")

for variable in ("SONARQUBE_DOCKER_IMAGE", "POSTGRES_IMAGE"):
    match = re.search(rf'^{variable}="([^"]+)"$', versions, re.MULTILINE)
    if not match or not re.fullmatch(r"[a-z0-9._/-]+@sha256:[0-9a-f]{64}", match.group(1)):
        failures.append(f"{variable} must be an immutable image digest.")
        continue

    image = match.group(1)
    occurrences = workflow.count(f"image: {image}")
    if occurrences != 2:
        failures.append(
            f"{variable} must be used by both vulnerability and SBOM CI jobs; found {occurrences} references."
        )

network_policy = ROOT / "deployments" / "kubernetes" / "common" / "network-policy.yaml.in"
policy_template = network_policy.read_text(encoding="utf-8")
for required in (
    "name: sonarweaver-default-deny",
    "name: sonarweaver-sonarqube",
    'app.kubernetes.io/instance: "@RELEASE@"',
    'cidr: "@DATABASE_EGRESS_CIDR@"',
    'port: 0 # @DATABASE_PORT@',
    "sonarweaver.io/network-access: monitoring",
):
    if required not in policy_template:
        failures.append(f"NetworkPolicy template is missing required production control: {required}")

kubernetes_installer = (ROOT / "deployments" / "kubernetes" / "scripts" / "install.sh").read_text(encoding="utf-8")
for required in (
    'helm list --namespace "$NAMESPACE" --filter "^$RELEASE$" --output json',
    "--upgrade-approved",
    "--backup-verified",
    "isolated restore verification",
    "--cert-manager-cluster-issuer",
    "ingress.annotations.cert-manager",
):
    if required not in kubernetes_installer:
        failures.append(f"Kubernetes installer is missing a required production control: {required}")

ansible_proxy_tasks = (ROOT / "ansible" / "roles" / "sonarweaver_proxy" / "tasks" / "main.yml").read_text(encoding="utf-8")
for required in (
    "sonarweaver_proxy_letsencrypt_enabled",
    "certbot",
    "--webroot",
    "sonarweaver-certbot-renew.timer",
):
    if required not in ansible_proxy_tasks:
        failures.append(f"Managed NGINX must retain the optional Let's Encrypt control: {required}")

gitleaks_config = ROOT / ".gitleaks.toml"
if not gitleaks_config.exists() or "679F1EE92B19609DE816FDE81DB198F93525EC1A" not in gitleaks_config.read_text(encoding="utf-8"):
    failures.append("Gitleaks must document the public SonarSource signing-key fingerprint false-positive exception.")

trivy_ignores = ROOT / ".trivyignore.yaml"
if not trivy_ignores.exists() or "CVE-2025-68121" not in trivy_ignores.read_text(encoding="utf-8") or "usr/local/bin/gosu" not in trivy_ignores.read_text(encoding="utf-8"):
    failures.append("Trivy must retain the scoped, expiring gosu exception for CVE-2025-68121.")

kubernetes_values = (ROOT / "deployments" / "kubernetes" / "common" / "values.yaml").read_text(encoding="utf-8")
for required in (
    "replicaCount: 1",
    "deploymentStrategy:\n  type: Recreate",
    "initSysctl:\n  enabled: false",
    "initFs:\n  enabled: false",
    "resources:\n  requests:\n    cpu: \"1\"\n    memory: 4Gi\n    ephemeral-storage: 2Gi\n  limits:\n    cpu: \"2\"\n    memory: 4Gi\n    ephemeral-storage: 10Gi",
    "serviceAccount:\n  create: true\n  automountToken: false",
):
    if required not in kubernetes_values:
        failures.append(f"Kubernetes values are missing required production control: {required!r}")

docker_evaluation = (ROOT / "deployments" / "docker" / "compose.local.yaml").read_text(encoding="utf-8")
for required in (
    "cap_drop:\n      - ALL",
    "cap_add:\n      - CHOWN\n      - SETGID\n      - SETUID",
):
    if required not in docker_evaluation:
        failures.append(f"Evaluation PostgreSQL must retain its reviewed least-privilege capability policy: {required!r}")

readiness_gates = (ROOT / "docs" / "production-readiness-gates.md").read_text(encoding="utf-8")
for required in (
    "| Delivery governance |",
    "Dependabot vulnerability alerts/security updates",
    "GitHub Actions SHA-pinning enforcement",
):
    if required not in readiness_gates:
        failures.append(f"Production acceptance guidance must retain the delivery-governance requirement: {required}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)

print("CI policy invariants passed.")
