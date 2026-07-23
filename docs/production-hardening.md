# Production hardening

Production readiness is a combination of host preparation, database design, identity, network policy, storage, backups, monitoring, and disciplined upgrades. Installing successfully is only the first step.

## Required production gates

Do not mark an instance production-ready until all of these are true:

- External supported database; embedded H2 is disabled
- Database backup and restore have been tested
- TLS is enforced at a maintained reverse proxy, Ingress, or Gateway
- Initial `admin/admin` credentials have been replaced
- Least-privilege user groups and authentication are configured
- Secrets are outside Git and redacted from logs
- SonarQube runs without root privileges
- Linux Elasticsearch kernel and process limits are persistent
- Fast storage has sufficient space and monitoring
- Plugins are minimized, pinned, and compatibility-reviewed
- A supported update path and maintenance procedure are documented

## Host and runtime

For a small installation, start with at least 2 CPU cores, 4 GB RAM, 30 GB disk, and 10% free disk. These are minimum starting values, not universal production sizing. Track analysis concurrency, compute-engine queue length, JVM pressure, database latency, and disk I/O.

Use a current JDK 21 or 25 CPU release for native ZIP installations. Run the service through a dedicated non-login identity on Linux/macOS or a dedicated low-privilege service identity on Windows. Application, configuration, data, and log paths should have the narrowest useful ownership and permissions.

Every Linux host or Kubernetes worker that can run SonarQube must persist:

```text
vm.max_map_count = 524288 or greater
fs.file-max      = 131072 or greater
service nofile   = 131072 or greater
service nproc    = 8192 or greater
```

Keep seccomp available and ensure the application has a writable temporary directory even when using a read-only root filesystem policy.

## Database

The database is the authoritative durable state. Operate it separately from the SonarQube host or cluster and keep network latency low.

- Use a database version supported by the exact SonarQube pin.
- Use UTF-8 and the database-specific settings required by SonarSource.
- Grant only the schema permissions SonarQube needs.
- Enforce TLS where the database deployment supports it.
- Restrict network access to the SonarQube workload and administration/backup paths.
- Monitor connections, storage growth, query latency, locks, and backup success.
- Do not reuse a schema between SonarQube instances.

Never pass a database password directly on a command line where it will enter shell history or process listings.

## Secrets and authentication

Treat these values as secrets:

- Database password
- Monitoring passcode
- Authentication JWT secret
- Administrator bootstrap credential
- DevOps-platform tokens and application private keys
- Commercial license data
- TLS private keys

Use permission-restricted files, Kubernetes Secrets integrated with the organization's secret manager, or another approved runtime-injection mechanism. Never commit real values to YAML, Compose files, environment examples, test fixtures, or issue reports.

Change the initial administrator password immediately. Prefer centralized authentication for team instances, disable or tightly control self-registration, give administration rights to a small group, and review access regularly.

## Network and TLS

Do not expose port 9000 directly to the public internet. Terminate TLS at a hardened reverse proxy, Ingress, or Gateway and limit direct backend access.

- Use a trusted certificate and a modern TLS policy.
- Treat automatic certificate issuance as an explicit infrastructure choice:
  use a pre-approved cert-manager ClusterIssuer for Kubernetes or a pre-approved
  Certbot installation for managed NGINX hosts, validate a staging issuance and
  renewal first, and retain ownership of DNS and firewall changes outside this
  toolkit.
- Preserve the correct forwarded host, scheme, and client information.
- Allow only required ingress from users, scanners, and integration callbacks.
- Allow only required egress to the database, identity provider, DevOps platforms, update/plugin sources, SMTP, and monitoring systems.
- Apply rate limits and request-size/time-out settings that do not break scanner report uploads.
- Keep the public base URL and any context path consistent across proxy and SonarQube configuration.

## Storage

Elasticsearch is sensitive to latency and free space. Prefer fast local SSD or an appropriate low-latency RWO block volume. Do not use NFS, SMB/CIFS, or NAS for the SonarQube Elasticsearch data path.

Alert before free space reaches the Elasticsearch watermarks. The upstream minimum is 10% free, but a capacity policy should provide more reaction time. The database, not Elasticsearch indexes, remains the backup priority.

Docker deployments should use named volumes for data, logs, and extensions. K3s `local-path` volumes are node-local and are not a production HA storage design.

## Container hardening

- Pin the official image by immutable digest; retain its reviewed version in the release record.
- Scan the exact image and configuration used for the release.
  - Keep the Compose `secrets/` directory restricted to its owner (`0700`). Docker Compose preserves the source mode of file-backed secrets, so the JDBC password file is deliberately `0644` to let SonarQube's non-root process read its mounted secret; do not loosen the directory ACL or place other files there.
  - Do not add an unreviewed package manager or debugging tools to the runtime image.
  - Drop unnecessary Linux capabilities and prevent privilege escalation. SonarQube drops all capabilities; the evaluation PostgreSQL entrypoint drops all except `CHOWN`, `SETGID`, and `SETUID`, which it requires only to initialize its volume and switch to the `postgres` user.
- Use read-only root filesystems where compatible, while supplying writable data, extension, log, and temporary paths.
- Define CPU/memory requests and limits based on measured load.

## Native Linux service sandbox

The managed systemd unit uses `ProtectSystem=strict` and permits writes only
to the configured data, log, and temporary directories. It also removes Linux
capabilities, uses private temporary and device namespaces, and restricts the
network address families to local Unix sockets plus IPv4/IPv6. Preserve these
controls when extending the unit; add an explicit, reviewed write path rather
than weakening the whole filesystem boundary.
- Keep credentials out of environment dumps and support bundles.

## RKE2 and K3s hardening

Use only Kubernetes versions 1.32 through 1.35 with the current official chart. The cluster itself must follow the organization's control-plane, etcd, node, RBAC, audit, encryption-at-rest, admission, and backup standards.

For a full restricted namespace:

1. Apply SonarQube's sysctls and file limits on every eligible worker node.
2. Pre-provision writable volume permissions.
3. Set `initSysctl.enabled=false` and `initFs.enabled=false`.
4. Enforce restricted Pod Security admission.
5. Use a dedicated ServiceAccount with minimal RBAC.
6. Apply default-deny ingress and egress NetworkPolicies, then permit only documented flows.
7. Use an independently managed Ingress or Gateway and cert-manager or another approved certificate process.
8. Place database and monitoring values in existing Secrets.
9. Constrain scheduling to prepared nodes and define disruption behavior deliberately.

Do not enable a deprecated bundled ingress controller merely for convenience. Discover and select a maintained cluster ingress or Gateway implementation.

SonarWeaver's production installer enforces this boundary with a default-deny
policy. It requires a database CIDR and allows DNS, database traffic, labelled
ingress-controller traffic, and labelled monitoring traffic only. Operators
must add reviewed policies before enabling external identity, SMTP, DevOps, or
other integration egress.

## Availability: what Kubernetes does and does not provide

The standard Community Build, Developer Edition, and Enterprise Edition chart supports one SonarQube application replica. A scheduler can recreate that pod elsewhere, but users will experience downtime during termination, attachment, startup, and Elasticsearch recovery.

Do not:

- Increase the standard chart to multiple application replicas
- Call node rescheduling active-active HA
- Call a node-local PVC highly available
- Treat a PodDisruptionBudget as application redundancy

True application and search-node redundancy requires licensed SonarQube Data Center Edition and its dedicated official architecture. Database HA, ingress HA, and durable storage still require separate design.

## Plugins and integrations

Install no plugin without a documented need. For each plugin, record version, source, checksum, license, compatible SonarQube versions, owner, and removal plan. Test upgrades without third-party plugins first when diagnosing incompatibility.

Rotate DevOps integration credentials and private keys. Grant integrations only the repository and organization permissions they need.

## Monitoring and operations

At minimum alert on:

- System/API health not `UP`
- Web, compute-engine, or Elasticsearch process failures
- Compute-engine queue growth and failed background tasks
- JVM heap and garbage-collection pressure
- CPU throttling or saturation
- Database connection and latency failures
- Disk latency, capacity, and Elasticsearch watermark events
- Pod restarts, failed scheduling, and PVC attachment failures
- TLS certificate expiry
- Backup age and restore-test age

For Kubernetes deployments with Prometheus Operator, configure the official
chart's secret-backed `monitoringPasscodeSecretName` and
`monitoringPasscodeSecretKey`, then enable its PodMonitor only after the
operator CRD is present. The monitoring system must authenticate to
`/api/monitoring/metrics` with the passcode and must not expose that passcode in
values files, labels, logs, or dashboards. See SonarSource's
[Prometheus setup guide](https://docs.sonarsource.com/sonarqube-server/2026.1/server-installation/on-kubernetes-or-openshift/set-up-monitoring/prometheus)
for the chart-specific metrics configuration.

Synchronize time on all server, database, proxy, and cluster nodes. Keep a change log that records SonarQube, Java, image, chart, database, plugin, and infrastructure versions.

## Supply-chain controls

- Pin downloads, images, charts, actions, and plugins.
- Verify published checksums or stored trusted digests before installation.
- Review automated version-update pull requests; do not auto-deploy them to production.
- Scan repository configuration for secrets and unsafe Kubernetes/Docker settings.
- Protect the default branch and require review for deployment changes.
- Preserve third-party license notices when mirroring artifacts.

GitHub Actions dependencies are reviewed through weekly Dependabot updates.
Keep action references immutable where the release process permits and review
automation updates with the same care as deployment code; an action can execute
with the workflow's permissions.

The pinned Python tools used only by CI are tracked in `requirements-ci.txt` and
are included in that weekly Dependabot review.

CI scans the exact immutable Compose image manifests and fails on fixable
critical vulnerabilities. Investigate any report before replacing a reviewed
digest; an image update must retain the corresponding SonarQube or PostgreSQL
compatibility and recovery validation.

The same checks run weekly, even when the repository has not changed, so newly
disclosed vulnerabilities in approved immutable images are surfaced for review.

The Kubernetes integration job also renders the production NetworkPolicy and
submits it to a disposable Kubernetes API with server-side dry-run validation.
Its Kind node image is also pinned by digest to keep the CI Kubernetes version
and image identity reproducible.

CI publishes an SPDX SBOM for each reviewed Compose image and retains the CI
artifact for 90 days. Retain the SBOMs with the release/change record so
vulnerability findings can be evaluated
against the exact deployed digest.

Run the production verification command from an approved administration host
after deployment and before accepting traffic:

```bash
./bin/sonarweaver verify \
  --url https://sonarqube.example.internal \
  --monitoring-passcode-file /run/secrets/sonarqube-monitoring-passcode
```

```powershell
.\bin\sonarweaver.ps1 verify `
  -Url https://sonarqube.example.internal `
  -MonitoringPasscodeFile C:\secure\sonarqube-monitoring-passcode
```

It requires HTTPS, checks that `/api/system/status` reports `UP`, and verifies
the protected monitoring endpoint without placing the passcode in command-line
arguments.

## Configuration management

For native Linux VM or bare-metal fleets, the optional SonarWeaver Ansible path
provides idempotent host preparation, a controlled release change gate, and
post-deployment API verification. Treat its inventory as sensitive operational
configuration: store production inventories and Vault material outside this
repository, use a least-privilege automation identity, and retain playbook logs
according to the organisation's change-record policy.

Ansible is not the Kubernetes release controller. For RKE2/K3s, commit reviewed
Helm values and use GitOps reconciliation; use Ansible only for node and
supporting-infrastructure configuration where it has clear ownership.

Continue with [backup, upgrade, and rollback](backup-upgrade.md) before accepting production traffic.
