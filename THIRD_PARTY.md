# Third-party software and licensing

SonarWeaver's original code and documentation are licensed under 0BSD. That license does not relicense software downloaded, referenced, or operated by SonarWeaver.

SonarWeaver does not need to vendor SonarQube binaries, container images, Helm chart packages, Java runtimes, databases, or Kubernetes distributions. Installations retrieve or use those components from their configured sources, and each component remains subject to its own license, support policy, export terms, trademarks, and commercial restrictions.

## Principal components

| Component | Project or publisher | Use in SonarWeaver | License or terms |
|---|---|---|---|
| SonarQube Community Build | SonarSource | Server runtime for the free channel | Upstream license and notices distributed by SonarSource |
| SonarQube Server Developer, Enterprise, and Data Center Editions | SonarSource | Optional commercial server channels | Applicable SonarSource commercial agreement and license |
| Official `sonarqube` container image | SonarSource / Docker Official Images | Docker and container runtime | Image contents retain their component licenses and SonarSource terms |
| `helm-chart-sonarqube` | SonarSource | RKE2 and K3s deployment dependency | MIT at the upstream chart repository at the time of this notice |
| PostgreSQL | PostgreSQL Global Development Group | Recommended external production database | PostgreSQL License |
| OpenJDK distributions | Their respective vendors and OpenJDK contributors | Native ZIP runtime | Vendor and OpenJDK license terms |
| Docker Engine and Docker Compose | Docker and upstream contributors | Compose deployment tooling | Applicable upstream licenses and Docker terms |
| Kubernetes | The Kubernetes Authors / CNCF | Cluster API targeted by the Helm deployment | Apache-2.0 |
| RKE2 and K3s | SUSE/Rancher and contributors | Supported Kubernetes distributions | Apache-2.0 for the upstream projects |

The table is an operational summary, not legal advice. Always inspect the exact artifact's bundled notices and current publisher terms before redistribution or production use.

## Version pins and integrity

Repository version pins identify compatible upstream artifacts; they do not transfer ownership. Where a checksum or image digest is supplied, SonarWeaver should verify it before use. Mirrors used in disconnected environments are responsible for preserving upstream notices and artifact integrity.

## Plugins

SonarQube plugins are separate works with independent licenses and compatibility requirements. SonarWeaver does not imply that any plugin is approved, supported, secure, or compatible. Review a plugin's source, license, release history, checksum, and compatibility matrix before installation.

## Trademarks

SonarQube, SonarSource, Docker, Kubernetes, RKE2, K3s, PostgreSQL, and other names belong to their respective owners. Their use describes compatibility only and does not imply endorsement.

## Upstream links

- [SonarQube downloads and product terms](https://www.sonarsource.com/products/sonarqube/downloads/)
- [Official SonarQube image](https://hub.docker.com/_/sonarqube)
- [Official SonarQube Helm chart](https://github.com/SonarSource/helm-chart-sonarqube)
- [PostgreSQL license](https://www.postgresql.org/about/licence/)
- [Kubernetes license](https://github.com/kubernetes/kubernetes/blob/master/LICENSE)
- [RKE2 repository](https://github.com/rancher/rke2)
- [K3s repository](https://github.com/k3s-io/k3s)
