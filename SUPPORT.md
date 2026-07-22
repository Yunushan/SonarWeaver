# Support policy

SonarWeaver is an unofficial community project maintained on a best-effort basis. It is not a substitute for SonarSource support, a SonarQube subscription, operating-system vendor support, or Kubernetes distribution support.

## Supported scope

Issues are in scope when they concern:

- SonarWeaver scripts, configuration, documentation, or generated deployment resources
- A platform and architecture marked supported in [the support matrix](docs/support-matrix.md)
- One of the pinned Community Build, Server latest, or Server LTA channels
- Docker, RKE2, or K3s versions inside the documented compatibility window
- A reproducible failure that occurs before unsupported local customization

The currently pinned versions are:

| Channel | Version |
|---|---:|
| Community Build | `26.7.0.124771` |
| Server latest | `2026.3.1` |
| Server LTA | `2026.1.3` |
| Official Helm chart | `2026.3.1` (`appVersion: 2026.3.1`) |

## Best-effort and out-of-scope cases

The following are documentation-only or best effort:

- Generic Unix platforms not listed by SonarSource, including BSDs, Solaris, AIX, and HP-UX
- End-of-life operating systems, Java versions, databases, Kubernetes versions, or SonarQube releases
- Third-party plugins, custom container images, modified Helm charts, and private forks
- Cloud-provider, storage-provider, ingress-controller, or database-provider incidents that cannot be reproduced with SonarWeaver
- Product licensing, commercial feature entitlement, or procurement questions
- Recovery where no valid database backup exists

Questions about the SonarQube product itself should go to the [Sonar Community](https://community.sonarsource.com/) or SonarSource support when the user has an eligible commercial subscription.

## Before opening an issue

Run the relevant preflight and collect:

1. SonarWeaver revision or release.
2. Deployment method: native, Docker, RKE2, or K3s.
3. SonarQube channel, version, and edition.
4. Operating system and architecture, or Kubernetes distribution and exact version.
5. Database type and version, without credentials.
6. The command that failed and its redacted output.
7. Relevant SonarQube logs and, for Kubernetes, pod events.
8. Whether the failure reproduces with third-party plugins disabled.

Search existing issues first and reduce the problem to the smallest safe reproduction. Do not post passwords, tokens, connection strings containing credentials, private certificates, private keys, commercial license data, environment files, or database dumps.

## Security reports

Do not create a public issue for a suspected vulnerability. Use the repository [security policy](SECURITY.md) or GitHub private vulnerability reporting if available. If neither route is available, open a minimal issue asking for a private contact without disclosing exploit details.

## Version lifecycle

SonarWeaver targets the versions pinned in the repository. When a pin changes, the previous pin may remain useful but is no longer part of the actively validated matrix unless it is explicitly retained in [docs/support-matrix.md](docs/support-matrix.md). Security and compatibility fixes are prioritized for the current pins.

No support statement in this repository extends the lifecycle promised by SonarSource, a database vendor, Docker, Kubernetes, SUSE/Rancher, or an operating-system vendor.
