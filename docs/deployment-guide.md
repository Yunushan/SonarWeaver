# Deployment guide

This guide helps choose and prepare a SonarWeaver deployment. Read [the support matrix](support-matrix.md) and [production hardening](production-hardening.md) first when the instance will serve a team.

## Choose a method

| Method | Best fit | Main trade-off |
|---|---|---|
| Native Linux | Dedicated VM, simple production operations, direct systemd integration | Host lifecycle and Java are your responsibility |
| Native Windows | Existing Windows-only operational environment | Fewer common SonarQube production patterns than Linux |
| Native macOS | Local evaluation and development | Not the recommended team-server platform |
| Docker Compose | Fast, repeatable single-host deployment | Compose is not a cluster or HA platform |
| RKE2 | Production-oriented Kubernetes already operated by the organization | Requires cluster, storage, ingress, secret, and node-kernel administration |
| K3s | Edge, lab, or smaller Kubernetes environment | Default local storage is node-local and not HA |
| Ansible native Linux | Managed VM or bare-metal fleet with audited, repeatable change control | Requires an Ansible control plane and secret-management integration |

Generic Unix is preflight-only because SonarSource does not publish a general FreeBSD, Solaris, AIX, HP-UX, or other Unix support statement.

## Shared prerequisites

Before using any method:

1. Select `community`, `server-latest`, or `server-lta` and keep the pinned version.
2. Size the host or pod. Start no lower than 2 CPU, 4 GB RAM, and 30 GB fast disk for a small instance.
3. Prepare a supported external database for production.
4. Create a dedicated database/schema and least-privilege SonarQube database account.
5. Decide the public URL, TLS endpoint, DNS name, and trusted proxy path.
6. Prepare a backup location and perform a restore test.
7. Decide how passwords, passcodes, tokens, and commercial licenses will be supplied without committing them.
8. Confirm that TCP 9000 is not exposed directly to untrusted networks.

The web server defaults to port 9000. The embedded H2 database is permitted only for disposable evaluation.

## Native installation

### Linux and macOS

Inspect the command interface:

```bash
chmod +x bin/sonarweaver
./bin/sonarweaver doctor linux
sudo ./bin/sonarweaver install linux --evaluation
./bin/sonarweaver status linux
```

This quick start uses disposable H2 evaluation mode. For production, omit `--evaluation` and provide all external database inputs:

```bash
sudo ./bin/sonarweaver install linux \
  --jdbc-url 'jdbc:postgresql://db.example.internal:5432/sonarqube' \
  --jdbc-user sonarqube \
  --jdbc-password-file /run/secrets/sonarqube-jdbc-password
```

Replace `linux` with `macos` on a supported Mac; macOS installation runs as the current user and does not need a leading `sudo`. `doctor unix` provides only generic Unix diagnostics; `install unix` is intentionally unavailable because those additional Unix platforms are not supported upstream.

Run the preflight before allowing an install. On Linux, verify all of these values on the actual host:

```bash
sysctl vm.max_map_count
sysctl fs.file-max
ulimit -n
ulimit -u
```

Required minima are `524288`, `131072`, `131072`, and `8192`, respectively. The SonarQube process must run as a dedicated non-root account. Do not install into a directory whose name starts with a digit.

For macOS, the open-file settings must reach 131072 for both the system and process. Native macOS is most appropriate for local evaluation.

The automated Linux path requires systemd. On a supported Linux distribution without `systemctl`, use the upstream manual service instructions; SonarWeaver does not claim automated service integration there.

The installation layout should keep these concerns separate:

- Versioned application binaries
- Persistent data and temporary paths
- Logs
- Configuration and secret references
- Plugins and optional JDBC drivers

This separation allows a new application version to be staged without treating the application directory as the backup.

### Windows

Open an elevated PowerShell only for steps that need service or ACL changes:

```powershell
.\bin\sonarweaver.ps1 doctor windows
.\bin\sonarweaver.ps1 install windows -Evaluation
.\bin\sonarweaver.ps1 status windows
```

The example uses disposable H2 evaluation mode. For production, omit `-Evaluation` and pass `-JdbcUrl`, `-JdbcUser`, and `-JdbcPasswordFile`. When a managed production installation already exists, complete the approved maintenance and isolated restore workflow first, then pass `-UpgradeApproved -BackupVerified`. Linux and macOS use the equivalent `--upgrade-approved --backup-verified` options. These are acknowledgement gates, not restore evidence.

Use a supported JDK 21 or 25, the low-privilege managed startup identity, and explicit NTFS permissions. SonarWeaver registers its startup task under Windows Local Service. Firewall changes should be opt-in and limited to the intended reverse proxy or administration network.

### Native production database settings

The relevant upstream properties are:

```properties
sonar.jdbc.url=jdbc:postgresql://db.example.internal:5432/sonarqube
sonar.jdbc.username=sonarqube
```

SonarWeaver reads the password from `--jdbc-password-file` and exposes it to the process at runtime as `SONAR_JDBC_PASSWORD`; it does not need to write the password into `sonar.properties`. Limit file permissions and encrypt sensitive SonarQube properties where applicable.

Secret input files must contain the exact secret bytes without a trailing CR or LF. Generate a simple file with `printf '%s' "$VALUE" > file` or configure the secret manager to omit line endings; do not use `echo`.

### Managed native Linux with Ansible

The optional [Ansible path](../ansible/README.md) is the preferred SonarWeaver
interface for a managed Linux VM or bare-metal fleet. It is production-only:
it requires a pinned release, external JDBC settings, and an existing protected
password file on each target. It manages the dedicated identity, persistent
kernel limits, installation staging, optional NGINX TLS proxy, service start,
and API health check.

Use an external secret manager or Ansible Vault to supply only the password
file path and related non-secret connection metadata. Do not place a password
in inventory or host variables. Ansible intentionally requires two explicit
operator assertions before an existing release is changed, after the
maintenance window and restore-tested backup have been completed.

For Kubernetes, Helm plus GitOps should own the SonarQube release. Ansible can
prepare worker-node prerequisites but must not become a competing source of
truth for Helm resources.

## Docker Compose

The Compose definition is at `deployments/docker/compose.yaml`.

The unified path is:

```bash
./bin/sonarweaver doctor docker
./bin/sonarweaver install docker evaluation --apply-sysctl
./bin/sonarweaver status docker evaluation
```

The direct bootstrap provides the same evaluation flow, creates an untracked `.env` and secret file when absent, and starts both SonarQube and the local evaluation database:

```bash
cd deployments/docker
./bootstrap.sh evaluation --apply-sysctl
docker compose --env-file .env -f compose.yaml -f compose.local.yaml config
```

For production, update the generated `.env` with the external JDBC URL and username, retain the password in `secrets/jdbc_password`, and run `./bootstrap.sh production`. Then inspect the stack:

```bash
docker compose --env-file .env -f compose.yaml ps
docker compose --env-file .env -f compose.yaml logs --tail=200 sonarqube
```

The definition should pin `sonarqube:26.7.0.124771-community` for the Community Build channel and use named volumes for:

- `/opt/sonarqube/data`
- `/opt/sonarqube/logs`
- `/opt/sonarqube/extensions`

SonarSource warns against bind mounts for those paths because they can prevent correct plugin initialization. Never use `docker compose down -v`, `docker volume prune`, or `docker system prune` without resolving and protecting every required volume first.

For production, point SonarQube to an independently operated supported database. A database container in the same Compose project is a convenience deployment, not the production reference architecture.

On POSIX hosts, the local `secrets/` directory is mode `0700`. Its JDBC
password file is mode `0644` because Docker Compose file-backed secrets
preserve the host file mode and the official SonarQube container runs as a
non-root user. Do not loosen the directory permission, copy the password
outside that directory, or use a world-accessible project directory. The
Windows bootstrap instead applies restrictive NTFS ACLs to the secret file.

If a production bootstrap would replace the image of an existing SonarQube
container, it stops until both `--upgrade-approved` and `--backup-verified`
are supplied. Use those acknowledgements only after completing the upgrade and
isolated restore steps in [backup and upgrade](backup-upgrade.md).
On PowerShell, use `-UpgradeApproved -BackupVerified` with
`./Bootstrap.ps1 -Mode production`, or through the wrapper:
`./bin/sonarweaver.ps1 install docker production -UpgradeApproved -BackupVerified`.

## RKE2 and K3s

### Cluster prerequisites

The cluster must already exist and be healthy. Confirm:

- Kubernetes minor version 1.32, 1.33, 1.34, or 1.35
- Helm 3 and a compatible `kubectl` on the administration host
- A default or explicitly selected fast RWO StorageClass
- An independently operated IngressClass or Gateway implementation
- DNS and TLS certificate strategy
- External database reachability
- Secure JDBC and monitoring input files, plus authorization to create or update the corresponding namespace Secrets
- Elasticsearch sysctls on every node eligible to run the SonarQube pod

List the actual cluster capabilities instead of assuming distribution defaults:

```bash
kubectl version
kubectl get nodes -o wide
kubectl get storageclass
kubectl get ingressclass
kubectl get gatewayclass 2>/dev/null || true
```

Kubernetes 1.36 is outside the current official chart range and should be rejected unless the operator deliberately accepts an unsupported configuration.

### Install path

Inspect the installer:

```bash
chmod +x deployments/kubernetes/scripts/install.sh
bash deployments/kubernetes/scripts/install.sh --help
```

The equivalent unified flow is:

```bash
./bin/sonarweaver doctor rke2
./bin/sonarweaver install rke2 --profile evaluation
./bin/sonarweaver status rke2
```

Replace `rke2` with `k3s` for a K3s context. This command uses disposable H2 evaluation mode. A production installation requires explicit database, secret, storage, and node-preparation inputs, for example:

```bash
./bin/sonarweaver install rke2 \
  --profile production \
  --jdbc-url 'jdbc:postgresql://db.example.internal:5432/sonarqube' \
  --jdbc-user sonarqube \
  --jdbc-password-file /run/secrets/sonarqube-jdbc-password \
  --monitoring-passcode-file /run/secrets/sonarqube-monitoring-passcode \
  --monitoring-namespace monitoring \
  --storage-class fast-rwo \
  --database-egress-cidr 10.42.0.10/32 \
  --node-prerequisites-ready
```

When that release already exists, complete the approved maintenance and
isolated database-restore workflow first, then add
`--upgrade-approved --backup-verified`. The installer verifies that the Helm
release exists before it creates or changes production resources. These flags
record an operator acknowledgement; they do not replace restore evidence.

For production ingress, add `--hostname`, `--ingress-class`,
`--ingress-namespace`, and `--tls-secret`; TLS is mandatory. The installer
labels the selected ingress-controller namespace to permit traffic only from
that namespace. The published official chart package is pinned to `2026.3.1`;
its Server `appVersion` is also `2026.3.1`.

To use an existing certificate, pre-create the named `--tls-secret`. To opt in
to Let's Encrypt through an existing cert-manager installation, keep
`--tls-secret sonar-example-com-tls` as the target Secret name and add
`--cert-manager-cluster-issuer letsencrypt-production` to the complete
production invocation above.

The installer verifies the ClusterIssuer and adds the standard
`cert-manager.io/cluster-issuer` Ingress annotation; cert-manager creates and
renews the TLS Secret. It never installs cert-manager, creates an ACME account,
or changes DNS/firewall rules. Test a staging issuer first, ensure the hostname
is publicly reachable on the selected HTTP-01 ingress class (or that the
ClusterIssuer is correctly configured for DNS-01), and allow the chosen ingress
controller to reach cert-manager's temporary solver Pods under the cluster's
NetworkPolicy design. Do not have another process manage the same TLS Secret.

Use common settings together with the matching distribution overlay:

- `deployments/kubernetes/common/`
- `deployments/kubernetes/rke2/`
- `deployments/kubernetes/k3s/`

Community Build requires the official chart values:

```yaml
community:
  enabled: true
  buildNumber: "26.7.0.124771"
```

Do not set a commercial `edition` value when deploying Community Build. Database credentials and the monitoring passcode must reference Kubernetes Secrets rather than appear in a committed values file.

For a restricted production namespace, configure the required kernel settings on the nodes and disable the chart's privileged filesystem and sysctl helpers:

```yaml
initSysctl:
  enabled: false
initFs:
  enabled: false
```

Do this only after confirming the nodes and persistent volume permissions already satisfy the requirements.

The production installer applies a default-deny NetworkPolicy, then permits
only DNS, TCP access to the explicit IPv4/IPv6 `--database-egress-cidr` and port, ingress
from the selected ingress-controller namespace, and monitoring from the
required `--monitoring-namespace`, which it labels
`sonarweaver.io/network-access=monitoring`. Add separately reviewed
NetworkPolicies for any identity provider, SMTP, DevOps platform, update source,
or other approved integration; egress remains denied until it is explicitly
allowed.

### RKE2 notes

RKE2 needs no special Helm wire protocol. Use the intended kubeconfig and context, then explicitly select the cluster's maintained ingress/Gateway and storage implementations. Do not assume an ingress controller solely from the RKE2 version.

### K3s notes

K3s commonly includes Traefik and the `local-path` provisioner. Use Traefik only after explicitly configuring the ingress route and TLS. Treat `local-path` as node-local evaluation storage, not an HA production volume.

Before a production installation, run the node prerequisite helper on every worker that may host SonarQube:

```bash
sudo deployments/kubernetes/scripts/node-prerequisites.sh --apply
sudo deployments/kubernetes/scripts/node-prerequisites.sh --check
```

The installer flag `--node-prerequisites-ready` is an operator assertion; it cannot prove that every eligible node was prepared. When enabling ingress, pass `--ingress-class` explicitly. The distribution-specific default is a convenience and does not prove that the class exists in the current cluster.

## Verify the result

Wait for the system API to report `UP`:

```bash
curl --fail --silent --show-error http://127.0.0.1:9000/api/system/status
```

For Kubernetes, check rollout, events, and logs through the selected namespace before exposing the route:

```bash
kubectl -n sonarqube get pods,pvc,service
kubectl -n sonarqube get events --sort-by=.lastTimestamp
kubectl -n sonarqube logs -l app.kubernetes.io/name=sonarqube --tail=200
```

Then:

1. Sign in through the protected URL.
2. Change the initial `admin/admin` credentials immediately.
3. Configure authentication and least-privilege groups.
4. Run a disposable sample scan.
5. Confirm compute-engine processing and database persistence.
6. Restart or reschedule once and verify that the instance recovers.
7. Record the installed versions and backup procedure.

## Removing an installation

SonarWeaver does not provide an automated destructive purge. Stop the application using the deployment method's normal control path, resolve every application/configuration/data target explicitly, and retain the external database and persistent data unless a separately approved retention decision says otherwise.

Back up and verify the database before any removal, even when retention is expected. Never use an unresolved environment variable, wildcard, broad recursive deletion, `docker compose down -v`, or namespace deletion as a shortcut.
