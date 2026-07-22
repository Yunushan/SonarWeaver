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

- Pin the official image by immutable version and, where maintained, digest.
- Scan the exact image and configuration used for the release.
- Do not add an unreviewed package manager or debugging tools to the runtime image.
- Drop unnecessary Linux capabilities and prevent privilege escalation.
- Use read-only root filesystems where compatible, while supplying writable data, extension, log, and temporary paths.
- Define CPU/memory requests and limits based on measured load.
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

Synchronize time on all server, database, proxy, and cluster nodes. Keep a change log that records SonarQube, Java, image, chart, database, plugin, and infrastructure versions.

## Supply-chain controls

- Pin downloads, images, charts, actions, and plugins.
- Verify published checksums or stored trusted digests before installation.
- Review automated version-update pull requests; do not auto-deploy them to production.
- Scan repository configuration for secrets and unsafe Kubernetes/Docker settings.
- Protect the default branch and require review for deployment changes.
- Preserve third-party license notices when mirroring artifacts.

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
