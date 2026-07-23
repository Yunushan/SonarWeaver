# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project intends to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) for published releases.

## [Unreleased]

### Added

- Initial cross-platform SonarQube installation and deployment toolkit.
- Native installation paths for supported Linux, Windows, and macOS hosts, plus a fail-closed generic Unix preflight.
- Docker Compose, K3s, and RKE2 deployment paths.
- Optional Ansible path for repeatable managed native-Linux installations.
- Optional Let's Encrypt certificate automation through an existing cert-manager ClusterIssuer for Kubernetes or an approved Certbot installation for managed NGINX hosts.
- Redaction-safe production acceptance record template and documented acceptance gates.
- CI coverage for shell, PowerShell, YAML, Ansible, Docker Compose, Helm rendering, disposable Kubernetes, workflow-security, secret, image-vulnerability, and SBOM checks.
- A disposable Docker runtime recovery canary that proves a PostgreSQL backup restores known data.

### Changed

- Production installations now require explicit acknowledgement before an existing deployment is upgraded, together with confirmation that a backup has been restore-verified.
- Docker and Kubernetes deployments use immutable reviewed image or chart identities and fail closed when required production inputs are absent.
- Ansible CI now selects its checked-in configuration explicitly, and its Molecule scenario validates without requiring a managed target.

### Security

- Hardened native, Docker, and Kubernetes paths with safer defaults for secrets, privileges, service exposure, filesystem writes, upgrade controls, and network policy.
- Docker evaluation PostgreSQL now uses a least-privilege capability set verified against real startup and recovery.
- Repository history is scanned for secrets; GitHub Actions are commit-pinned; reviewed image digests are scanned for fixable critical vulnerabilities and have retained SBOMs.

[Unreleased]: https://github.com/Yunushan/SonarWeaver/commits/main
