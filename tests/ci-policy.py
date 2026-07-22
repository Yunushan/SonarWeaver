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

for requirement in (
    "ansible-core==2.20.2",
    "ansible-lint==25.12.0",
    "molecule==25.12.0",
    "zizmor==1.18.0",
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

if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)

print("CI policy invariants passed.")
