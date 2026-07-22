# SonarWeaver

SonarWeaver is an unofficial, reproducible deployment toolkit for SonarQube Community Build and SonarQube Server. It covers native installations on supported operating systems, Docker Compose, and deployments to existing RKE2 or K3s clusters.

> [!IMPORTANT]
> SonarWeaver is a community project. It is not affiliated with, sponsored by, or supported by SonarSource. SonarQube and SonarSource are trademarks of their owner.

## What it provides

- Native automation for Linux, Windows, and macOS
- A Docker Compose deployment with persistent volumes
- Official Helm chart integration for RKE2 and K3s
- Optional Ansible production path for managed native Linux hosts
- Preflight checks for platform, Java, Linux kernel limits, deployment configuration, and Kubernetes compatibility
- Pinned product versions instead of floating production tags
- Operational guidance for TLS, secrets, backups, upgrades, rollback, and troubleshooting
- Safe defaults: production rejects H2, destructive data removal is not automated, and generic Unix is never presented as upstream-supported

## Pinned release channels

| Channel | Pinned version | Intended use |
|---|---:|---|
| Community Build | `26.7.0.124771` | Free Community Build; monthly release stream with no LTA channel |
| Server latest | `2026.3.1` | Current Developer, Enterprise, or Data Center release |
| Server LTA | `2026.1.3` | Commercial Long-Term Active release |
| Official Helm chart | `2026.3.1` | Published chart release; its Server `appVersion` is also `2026.3.1` |

Production deployments should use an explicitly pinned channel and version. [`config/versions.env`](config/versions.env) is the repository's compatibility lock; SonarWeaver does not silently follow `latest`.

## Support snapshot

| Target | Architectures | SonarWeaver status |
|---|---|---|
| Linux native | x64, AArch64 | Supported |
| Windows native | x64 | Supported |
| macOS native | x64, AArch64 | Supported |
| Other Unix, including FreeBSD, OpenBSD, Solaris, AIX, and HP-UX | Varies | Preflight and documentation only; not supported upstream |
| Docker | amd64, arm64/v8 Linux containers | Supported |
| RKE2 | Kubernetes 1.32-1.35 | Supported on an existing cluster |
| K3s | Kubernetes 1.32-1.35 | Supported on an existing cluster |

Linux and macOS satisfy the supported Unix-family use cases. A generic Unix preflight must not be interpreted as compatibility with operating systems for which SonarSource publishes no supported runtime. See the complete [support matrix](docs/support-matrix.md).

## Before installing

For a small instance, start with at least 2 CPU cores, 4 GB RAM, 30 GB fast local disk, and 10% free disk space. Native ZIP installations require a current JDK 21 or 25 CPU release. Linux native automation currently targets systemd-based distributions.

Every production deployment requires:

- A supported external database; the reference path uses PostgreSQL
- Low latency between SonarQube and its database
- TLS through a reverse proxy, Ingress, or Gateway
- A tested database backup and restore procedure
- Immediate replacement of the initial `admin/admin` credentials

The embedded H2 database is for disposable evaluation only. It is not supported by this project for production.

On Linux nodes that run SonarQube, the minimum Elasticsearch-related limits are:

```text
vm.max_map_count >= 524288
fs.file-max      >= 131072
nofile           >= 131072
nproc            >= 8192
```

Run the preflight before installation. Do not place the Elasticsearch data directory on NFS, SMB/CIFS, or NAS storage.

## Quick starts

Clone the repository and inspect the relevant entry point before making changes:

```bash
git clone https://github.com/Yunushan/SonarWeaver.git
cd SonarWeaver
chmod +x bin/sonarweaver deployments/kubernetes/scripts/install.sh
./bin/sonarweaver --help
```

On Windows PowerShell:

```powershell
git clone https://github.com/Yunushan/SonarWeaver.git
Set-Location SonarWeaver
.\bin\sonarweaver.ps1 doctor windows
```

### Native

Use the platform entry point to run preflight, install, and inspect status. Replace `linux` with `macos` where appropriate:

```bash
./bin/sonarweaver doctor linux
sudo ./bin/sonarweaver install linux --evaluation
./bin/sonarweaver status linux
```

```powershell
.\bin\sonarweaver.ps1 doctor windows
.\bin\sonarweaver.ps1 install windows -Evaluation
.\bin\sonarweaver.ps1 status windows
```

These commands use disposable H2 evaluation mode. Production is the default installation mode and requires external JDBC options. Native automation installs a versioned application directory, keeps mutable data separate, and configures a systemd service, macOS LaunchAgent, or Windows managed startup task. Review the [deployment guide](docs/deployment-guide.md) before using it on a production host.

### Docker Compose

Review all interpolated values, then start the stack:

```bash
./bin/sonarweaver doctor docker
./bin/sonarweaver install docker evaluation --apply-sysctl
./bin/sonarweaver status docker

# Direct access to deployments/docker/compose.yaml remains available:
(cd deployments/docker && ./bootstrap.sh evaluation --apply-sysctl)
```

The bootstrap creates an untracked `.env` and password file if needed. Set production database settings there or through your secret-management workflow, and use `production` instead of `evaluation`. Do not commit secrets. Never run `docker compose down -v` against an installation whose volumes you need.

`--apply-sysctl` changes the current Linux host values and may request `sudo`; omit it when an administrator has already applied the required values persistently.

### RKE2 or K3s

The Kubernetes installer deploys SonarQube into an existing cluster; it does not create or administer the RKE2/K3s cluster itself.

```bash
bash deployments/kubernetes/scripts/install.sh --help

# Or use the unified entry point:
./bin/sonarweaver doctor rke2
./bin/sonarweaver install rke2 --profile evaluation
./bin/sonarweaver status rke2
```

Replace `rke2` with `k3s` for K3s. This quick start is disposable H2 evaluation mode. Use the matching values overlay under `deployments/kubernetes/rke2/` or `deployments/kubernetes/k3s/`. The production installer validates that the current Kubernetes minor version is between 1.32 and 1.35 and requires explicit storage, node-readiness, database, and secret-file inputs.

### Managed Linux with Ansible

For production native Linux hosts managed as a fleet, use the optional
[Ansible path](ansible/README.md). It applies host prerequisites, performs a
pinned external-database installation, optionally configures NGINX TLS, and
waits for the service API to become healthy. It does not replace the CLI for
local use or Helm/GitOps as the source of truth for Kubernetes releases.

## Kubernetes availability boundary

RKE2 or K3s can reschedule a failed single SonarQube pod, but that is not active-active application high availability. Community Build, Developer Edition, and Enterprise Edition use a single SonarQube application replica with the standard chart. True SonarQube application clustering and horizontal redundancy require a licensed Data Center Edition deployment and its dedicated official chart.

Node-local K3s `local-path` volumes are useful for evaluation but are not HA storage. Production storage must match the failure and recovery objectives of the environment.

## Documentation

- [Platform and version support](docs/support-matrix.md)
- [Native, Docker, RKE2, and K3s deployment guide](docs/deployment-guide.md)
- [Production hardening](docs/production-hardening.md)
- [Production acceptance gates](docs/production-readiness-gates.md)
- [Backup, upgrade, and rollback](docs/backup-upgrade.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Project support policy](SUPPORT.md)
- [Third-party software and licenses](THIRD_PARTY.md)

## Version and update policy

Pinned versions are reviewed deliberately. Automated dependency checks may propose updates, but production version changes should not be merged until native, Compose, and Kubernetes validation succeeds. SonarQube update paths and plugin compatibility must be checked against the official release notes before every upgrade.

## Security

Do not report a vulnerability in a public issue. Follow the repository [security policy](SECURITY.md) or GitHub private vulnerability reporting if it is enabled. Never attach live secrets, full environment files, database dumps, license files, or unredacted logs to an issue.

## License

Original SonarWeaver code and documentation are released under the [Zero-Clause BSD license](LICENSE). Downloaded SonarQube software, images, charts, databases, and other dependencies retain their own licenses and terms; see [THIRD_PARTY.md](THIRD_PARTY.md).

## Official references

- [SonarQube Community Build host requirements](https://docs.sonarsource.com/sonarqube-community-build/server-installation/server-host-requirements)
- [Installing Community Build from a ZIP file](https://docs.sonarsource.com/sonarqube-community-build/server-installation/from-zip-file/basic-installation)
- [Installing Community Build from Docker](https://docs.sonarsource.com/sonarqube-community-build/server-installation/from-docker-image/installation-overview)
- [Installing the official Helm chart](https://docs.sonarsource.com/sonarqube-community-build/server-installation/on-kubernetes-or-openshift/installing-helm-chart)
- [Official SonarSource Helm chart repository](https://github.com/SonarSource/helm-chart-sonarqube)
