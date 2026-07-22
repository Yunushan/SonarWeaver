# Security Policy

SonarWeaver contains deployment automation that may run with elevated privileges or configure
externally reachable services. Please report security problems privately.

## Supported versions

Security fixes are applied to the current default branch and, after releases begin, the latest release.
Older snapshots and downstream forks are not maintained by this project.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/Yunushan/SonarWeaver/security/advisories/new)
when it is available. If private reporting is unavailable, contact the repository owner through the
contact method listed on the [Yunushan GitHub profile](https://github.com/Yunushan) and ask for a private
security channel.

Do not open a public issue or pull request containing exploit details, credentials, private infrastructure
information, or an unpatched vulnerability.

Please include:

- the affected file, version, and deployment path;
- prerequisites and a minimal reproduction;
- the security impact and likely attack scenario;
- suggested mitigations, if known; and
- whether the issue has been disclosed elsewhere.

Reports will be acknowledged as soon as practical. Disclosure timing will be coordinated after the issue
is reproduced and a fix or mitigation is available.

## Scope

In scope are vulnerabilities introduced by this repository, including unsafe command construction,
privilege escalation, secret exposure, insecure defaults, unverified downloads, and deployment manifests
that unintentionally expose SonarQube or PostgreSQL.

Vulnerabilities in SonarQube itself, its official images, or its official Helm chart should also be reported
to SonarSource through its published security process. Problems in Docker, Kubernetes, K3s, RKE2,
PostgreSQL, operating systems, or third-party dependencies should be reported to their respective
maintainers. We still welcome a private notice when SonarWeaver needs a version pin, mitigation, or
documentation update.

## Handling sensitive material

Before sharing diagnostics, redact passwords, tokens, cookies, database URLs, private keys, certificates,
internal addresses, organization names, and source-code findings. Rotate any credential that may have
been exposed.
