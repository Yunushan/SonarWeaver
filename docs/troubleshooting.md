# Troubleshooting

Start with the least invasive evidence. Do not delete data, recreate volumes, clear Elasticsearch directories, or restore a database until the target and consequences are understood.

## Diagnostic order

1. Confirm the selected product channel and exact version.
2. Run SonarWeaver preflight again.
3. Check host or cluster resources, disk free space, and time synchronization.
4. Check database reachability and authentication without exposing the password.
5. Inspect the SonarQube system status endpoint.
6. Read `sonar`, `web`, `ce`, and `es` logs in that order.
7. Disable third-party plugins in a controlled test if startup compatibility is suspected.
8. Compare the running configuration with the last known-good version.

The health endpoint is:

```bash
curl --fail --silent --show-error http://127.0.0.1:9000/api/system/status
```

During startup it may report a non-`UP` state before becoming ready. Poll with a bounded timeout rather than assuming a fixed startup duration.

## Find logs

### Native

SonarWeaver's default log directories are `/var/log/sonarqube` on Linux, `~/Library/Application Support/SonarWeaver/logs` on macOS, and `C:\ProgramData\SonarWeaver\logs` on Windows. They contain:

```text
sonar.log
web.log
ce.log
es.log
```

Also inspect the platform service manager:

```bash
systemctl status sonarqube --no-pager
journalctl -u sonarqube --since "30 minutes ago" --no-pager
```

On Windows, inspect the SonarQube logs and the `SonarWeaver-SonarQube` scheduled task state. Redact account names or paths only when they disclose sensitive internal information; preserve enough context to diagnose permissions.

### Docker Compose

```bash
./bin/sonarweaver status docker
cd deployments/docker
docker compose --env-file .env -f compose.yaml -f compose.local.yaml logs --tail=300 sonarqube
container_id=$(docker compose --env-file .env -f compose.yaml -f compose.local.yaml ps -q sonarqube)
docker inspect "$container_id" --format '{{json .State}}'
```

The example includes the local evaluation overlay. Omit `-f compose.local.yaml` for an external-database production deployment. Container names may differ when a Compose project name is used; resolving the service ID avoids assuming a name.

### RKE2 and K3s

```bash
kubectl -n sonarqube get pods,pvc,service -o wide
kubectl -n sonarqube describe pod -l app.kubernetes.io/name=sonarqube
kubectl -n sonarqube get events --sort-by=.lastTimestamp
kubectl -n sonarqube logs -l app.kubernetes.io/name=sonarqube --all-containers --tail=300
```

If an init container fails, inspect that container specifically with `kubectl logs POD -c CONTAINER`. Do not repeatedly restart it without resolving the failed prerequisite.

## Common failures

### Unsupported operating system or architecture

Official native support is Linux x64/AArch64, Windows x64, and macOS x64/AArch64. Generic Unix is preflight-only. Do not bypass the platform gate on BSD, Solaris, AIX, HP-UX, or z/OS and then report the resulting native-library failure as a supported installation.

### Wrong Java version

Pinned native releases require JDK 21 or 25. Check both the interactive shell and service environment:

```bash
java -version
```

The service can use a different PATH or explicit Java path. After changing Java, restart cleanly and record the exact vendor and patch level.

### SonarQube is running as root

SonarQube must not run as root on Unix-family systems. Create a dedicated account, correct ownership on application/data/log/temp paths, and run the service under that identity. Do not weaken the check.

### Elasticsearch bootstrap check failure

Typical log messages mention `vm.max_map_count`, open files, or process/thread limits. Verify on the host or Kubernetes worker that actually runs the process:

```bash
sysctl vm.max_map_count
sysctl fs.file-max
ulimit -n
ulimit -u
```

Required minima are 524288, 131072, 131072, and 8192. Container-level settings cannot compensate for a host kernel value that is too low.

### Database connection failure

Check DNS resolution, routing, firewall policy, TLS trust, JDBC URL, username, database existence, schema permissions, and supported database version. Confirm the database is UTF-8. Test connectivity without printing the password.

Errors such as authentication failure, connection refused, timeout, certificate path failure, and too many connections have different causes; preserve the exact redacted error text.

### Port 9000 is unavailable

Resolve the current listener before changing configuration:

```bash
ss -ltnp | grep ':9000' || true
```

On Windows use `Get-NetTCPConnection -LocalPort 9000`. Change the port or stop the correctly identified conflicting service; do not terminate an unknown process blindly.

### Permission denied on data, logs, extensions, or temp

Confirm the runtime UID/account and the ownership/mode of each mounted or native path. On Kubernetes, also inspect the StorageClass, volume mode, security context, and failed init-container logs. Avoid recursively changing ownership across an unresolved broad path.

### Docker plugins or extensions do not initialize

Use named Docker volumes for `/opt/sonarqube/data`, `/opt/sonarqube/logs`, and `/opt/sonarqube/extensions`. SonarSource warns that bind mounts can prevent correct initialization. Confirm volume ownership and plugin compatibility.

Do not solve the problem with `docker compose down -v`; it removes volumes.

### Disk watermark or read-only behavior

Check database and Elasticsearch storage capacity and latency. Restore free space safely, identify growth, and raise capacity before restarting repeatedly. Keep at least 10% free; production alerting should trigger earlier. Do not delete Elasticsearch files manually.

### Kubernetes pod remains Pending

Inspect pod events and PVC state. Common causes are:

- No matching StorageClass
- An unbound PVC
- Insufficient CPU or memory
- Node selectors, affinity, or taints with no eligible node
- Volume topology preventing attachment

K3s `local-path` volumes remain tied to a node. Scheduling a pod elsewhere cannot attach data that exists only on the failed node.

### Kubernetes init container is forbidden

A restricted namespace may reject privileged `init-sysctl` or filesystem helpers. Configure sysctls on every eligible worker, pre-provision volume permissions, then disable `initSysctl` and `initFs` in chart values. Do not relax namespace security without an approved risk decision.

### Kubernetes version rejected

The current official Helm chart range is Kubernetes 1.32-1.35. RKE2 or K3s 1.36 is outside that range even if the distribution itself is available. Select a supported cluster version or wait for an updated validated chart.

### Readiness takes too long

Startup time grows when Elasticsearch indexes must be rebuilt. Check CPU throttling, database latency, storage latency, and available memory before increasing probe timeouts. Persistence can improve restart time but does not replace database backups and introduces its own recovery considerations.

### Reverse proxy returns 502, redirects incorrectly, or loses sessions

Confirm backend reachability, proxy timeouts, forwarded host/scheme headers, public base URL, context path, request size, and authentication JWT configuration. Scanner report uploads may need longer timeouts and larger request limits than ordinary UI traffic.

### Initial login fails

The initial credentials are `admin/admin` only on a new installation. If they were already changed, use the approved recovery procedure; do not reset or replace the production database. After initial access, change the password immediately.

## Safe issue report

Include:

- SonarWeaver revision
- Deployment method
- SonarQube product, edition, and exact version
- OS/architecture or RKE2/K3s and Kubernetes version
- Database product and version
- Redacted command output
- Relevant log section with timestamps
- Pod events for Kubernetes
- Third-party plugin inventory

Exclude passwords, tokens, JDBC credentials, private keys, environment files, database dumps, commercial license material, and internal data unrelated to the failure. See [the support policy](../SUPPORT.md).
