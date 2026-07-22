# Contributing to SonarWeaver

Thank you for helping make SonarQube deployments safer and easier to reproduce.

## Before you start

- Search existing issues before proposing a change.
- Open an issue first for a large feature or a change to supported platforms.
- Keep each pull request focused on one problem.
- Never commit real passwords, tokens, private keys, certificates, hostnames, or production data.
- Do not present a generic Unix platform as supported unless SonarSource adds it to the support matrix
  and the installation path is tested.

This project is independent and is not affiliated with or endorsed by SonarSource. Changes must not imply otherwise.

## Development setup

Use the same checks that run in continuous integration. The tools required for the complete suite are:

- ShellCheck
- Windows PowerShell 5.1 or PowerShell 7, plus PSScriptAnalyzer
- yamllint
- Docker with the Compose plugin
- Helm 3
- Kind for the disposable Kubernetes integration test
- Ansible, ansible-lint, and Molecule for changes under `ansible/`

Run the relevant checks for every file you change. The CI workflow contains the canonical commands and validates:

- all tracked shell scripts with ShellCheck;
- native Linux installer production/evaluation contract checks;
- Windows installer security-invariant checks;
- PowerShell parsing and PSScriptAnalyzer findings;
- repository YAML with yamllint;
- Docker Compose rendering without starting containers; and
- a disposable Docker Compose evaluation deployment that must report API status `UP`;
- a disposable Kubernetes evaluation deployment that must report API status `UP`;
- K3s and RKE2 values by rendering the pinned official SonarSource Helm chart.
- Ansible linting and playbook/Molecule syntax for the optional managed-Linux path.
- GitHub Actions policy and repository-history secret scanning.
- CI policy invariants for pinned runners, action commits, and image digests.

Tests must not install or start SonarQube, modify host kernel settings, or connect to a production database.

## Change guidelines

### Installation scripts

- Make operations idempotent whenever practical.
- Fail early with an actionable error message.
- Quote paths and variables, including on Windows.
- Verify downloaded artifacts before use.
- Do not silently weaken TLS, authentication, file permissions, or container security.
- Add a dry-run or preflight path for privileged operations when possible.
- Preserve data during upgrade and removal workflows unless the user explicitly requests deletion.

### Docker and Kubernetes

- Pin deployable component versions; avoid floating production tags.
- Keep credentials in environment variables or external secret objects, never committed manifests.
- Render and validate configuration without contacting a live cluster.
- Do not describe a single SonarQube application replica as highly available.
- Keep distribution-specific K3s and RKE2 behavior in their respective overlays.

### Documentation

- State whether a platform is upstream-supported, community-tested, or experimental.
- Include prerequisites, validation, backup, upgrade, rollback, and removal implications.
- Use placeholders such as `sonarqube.example.com` and `CHANGE_ME`; never copy production values.

## Pull requests

A pull request should include:

1. A concise explanation of the problem and approach.
2. The deployment paths and operating systems affected.
3. Commands or automated checks used for validation.
4. Security, compatibility, upgrade, and rollback considerations.
5. Documentation updates when behavior changes.

By contributing, you agree that your contribution is provided under the repository's 0BSD license.
