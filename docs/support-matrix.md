# Support matrix

This document separates upstream SonarQube compatibility from the automation provided by SonarWeaver. “Supported” means that SonarSource lists the platform and SonarWeaver has an installation path for it; it does not create a commercial support obligation.

Matrix reviewed: 2026-07-22.

## Product channels

| SonarWeaver channel | Product | Pinned version | Release model |
|---|---|---:|---|
| `community` | SonarQube Community Build | `26.7.0.124771` | Monthly; no LTA channel |
| `server-latest` | SonarQube Server | `2026.3.1` | Latest commercial release |
| `server-lta` | SonarQube Server LTA | `2026.1.3` | Commercial Long-Term Active release |

The pinned published official Helm chart is `2026.3.1`. A chart package version and the application version are separate values even though this chart's Server `appVersion` is also `2026.3.1`; Community Build is selected with `community.enabled=true` and the build number below.

Developer, Enterprise, and Data Center features require the corresponding valid SonarSource license. SonarWeaver does not supply, bypass, or modify licensing.

## Native platforms

| Operating system | Architecture | Upstream status | SonarWeaver coverage |
|---|---|---|---|
| Linux | x86-64 | Supported | Native ZIP, preflight, configuration, and systemd service automation |
| Linux | AArch64 | Supported | Native ZIP, preflight, configuration, and systemd service automation |
| Windows | x86-64 | Supported | Native ZIP, preflight, configuration, and managed startup task automation |
| macOS | x86-64 | Supported | Native ZIP, preflight, and local service guidance |
| macOS | AArch64 / Apple Silicon | Supported | Native ZIP, preflight, and local service guidance |
| FreeBSD, OpenBSD, NetBSD | Any | Not listed as supported | Preflight and documentation only; installation must fail closed |
| Solaris, AIX, HP-UX | Any | Not listed as supported | Preflight and documentation only; installation must fail closed |
| z/OS | Any | Explicitly unsupported | Not supported |

The upstream page titled “Unix-based systems” describes non-root operation. It does not declare every Unix implementation compatible. Linux and macOS are the supported Unix-family platforms.

Native ZIP installs require a JDK. For the pinned releases, use Java 21 or Java 25 and keep the selected JDK on a current critical-patch update.

SonarSource documents other Unix service arrangements, but SonarWeaver's automated Linux path currently requires `systemctl`. Non-systemd Linux installations need manual service integration and are outside the automated path.

## Docker

| Item | Supported value |
|---|---|
| Engine | Docker Engine 20.10 or newer |
| Compose | Docker Compose v2 |
| Container architecture | `linux/amd64`, `linux/arm64/v8` |
| Community image pin | `sonarqube:26.7.0.124771-community` |
| Persistence | Named volumes for data, logs, and extensions |
| Production database | External supported database required |

On Windows and macOS, the official image runs as a Linux container through Docker Desktop or another Linux-container runtime. It is not a Windows container.

H2 is allowed only for a disposable evaluation. A Compose stack that contains PostgreSQL on the same host may be useful for development or a small non-critical environment, but the production reference design uses a separately operated database.

## Kubernetes, RKE2, and K3s

| Item | Supported value |
|---|---|
| Official chart | SonarSource `sonarqube` chart `2026.3.1` |
| Chart Server `appVersion` | `2026.3.1` |
| Kubernetes API range | 1.32 through 1.35 |
| Community chart setting | `community.enabled=true` |
| Community build pin | `community.buildNumber=26.7.0.124771` |
| RKE2 | Releases based on Kubernetes 1.32-1.35 |
| K3s | Releases based on Kubernetes 1.32-1.35 |
| Kubernetes 1.36+ | Outside the current official chart range; reject or require an explicit unsupported override |
| Production database | External supported database and Kubernetes Secret required |
| Production ingress | Independently managed Ingress or Gateway required |

SonarWeaver deploys to an existing RKE2 or K3s cluster. It does not install, upgrade, secure, back up, or repair the Kubernetes distribution itself.

Do not assume an IngressClass or StorageClass merely from the distribution name. Preflight should discover them and require an explicit selection. K3s `local-path` storage is node-local and must not be described as highly available.

## Database support

SonarWeaver's production reference path is external PostgreSQL. Current Community Build documentation supports PostgreSQL 14 through 18, using UTF-8. Check the exact upstream database matrix again when changing the SonarQube pin.

Commercial editions may support additional database products. Passing through those connection settings does not mean SonarWeaver installs, licenses, tunes, backs up, or validates the external database product.

| Database mode | Evaluation | Production |
|---|---:|---:|
| Embedded H2 | Yes, disposable only | No |
| PostgreSQL in the same Compose project | Yes | Not the reference design |
| Separately operated supported PostgreSQL | Yes | Yes |
| Other database supported by the selected commercial edition | Optional | Follow upstream requirements |

## Availability and scaling

The standard chart for Community Build, Developer Edition, and Enterprise Edition operates one SonarQube application replica. Kubernetes rescheduling can improve recoverability after node failure, but it does not make the application active-active and does not remove startup or recovery downtime.

True SonarQube application-node and search-node redundancy requires licensed Data Center Edition and its dedicated official deployment architecture. SonarWeaver must not generate multiple standard-chart replicas or label them HA.

## Hardware baseline

For a small instance of roughly up to one million lines of code, the upstream starting point is:

- 2 CPU cores
- 4 GB RAM
- 30 GB disk
- At least 10% free disk space
- Fast local SSD-backed storage for Elasticsearch data

This is a starting point, not a capacity guarantee. Measure compute-engine backlog, scan concurrency, database performance, JVM memory, and disk latency, then resize from observed demand.

## Authoritative references

- [Community Build server host requirements](https://docs.sonarsource.com/sonarqube-community-build/server-installation/server-host-requirements)
- [Community Build database requirements](https://docs.sonarsource.com/sonarqube-community-build/server-installation/installing-the-database)
- [Official Helm chart README](https://github.com/SonarSource/helm-chart-sonarqube/blob/master/charts/sonarqube/README.md)
- [Kubernetes installation prerequisites](https://docs.sonarsource.com/sonarqube-community-build/server-installation/on-kubernetes-or-openshift/before-you-start)
