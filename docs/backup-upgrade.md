# Backup, upgrade, and rollback

The SonarQube database is the authoritative state. An application directory, container image, Helm release, or Elasticsearch data volume is not a substitute for a consistent database backup.

## What to protect

Back up or record:

1. The complete SonarQube database using the database vendor's consistent backup method.
2. The exact SonarQube product, edition, and version.
3. Configuration and encrypted sensitive-property material needed to read it.
4. Installed plugin names, versions, sources, licenses, and checksums.
5. Custom trust stores, certificates, proxy settings, and optional JDBC drivers.
6. Service, Compose, Helm values, Kubernetes manifests, and secret object names.
7. External identity-provider and DevOps-integration configuration needed for recovery.

Protect backups with encryption, access control, retention, and off-host copies. A backup is not trusted until a restore has succeeded in an isolated environment.

## PostgreSQL example

Use your database platform's standard backup tooling and organizational policy. A typical logical backup is:

```bash
pg_dump --format=custom --file=sonarqube-YYYYMMDD.dump --dbname=sonarqube
```

Supply authentication through a protected password file, runtime secret, or managed identity mechanism rather than embedding a password in the command. For large databases, use the organization's physical backup and point-in-time recovery design instead of assuming a logical dump is sufficient.

Test restore to a separate database:

```bash
createdb sonarqube_restore_test
pg_restore --exit-on-error --clean --if-exists \
  --dbname=sonarqube_restore_test sonarqube-YYYYMMDD.dump
```

Adjust ownership and connection options for the actual environment. Never run a restore test over the production database.

## Method-specific notes

### Native

Record the versioned application path and archive the configuration, plugin inventory, trust material, and service definition. Persistent Elasticsearch data can reduce recovery time, but a compatible SonarQube version plus the restored database is the basis of recovery.

Do not copy live database files or a live application directory and call that a consistent backup.

### Docker Compose

Record the rendered Compose configuration with secrets redacted, exact image digest, external database endpoint, and named-volume identities.

Avoid these commands unless every target has been resolved and intentionally approved:

```text
docker compose down -v
docker volume prune
docker system prune --volumes
```

They can permanently remove database or SonarQube volumes. Stopping the stack with `docker compose stop` or a non-volume-removing `down` is safer when preparing maintenance.

When `./bootstrap.sh production` detects that the requested immutable
SonarQube image differs from a running container, it requires
`--upgrade-approved --backup-verified`. This is an acknowledgement gate, not a
substitute for a tested restore; use it only after completing the workflow
below.

The Kubernetes installer applies the same acknowledgement gate before changing
an existing production Helm release. After the workflow below, re-run it with
`--upgrade-approved --backup-verified`; a first production installation and a
`--dry-run` do not require the flags.

Direct native installers also require these acknowledgements when a managed
production installation exists: `--upgrade-approved --backup-verified` on
Linux/macOS or `-UpgradeApproved -BackupVerified` on Windows.

### RKE2 and K3s

Record:

```bash
helm -n sonarqube list
helm -n sonarqube get values sonarqube --all
helm -n sonarqube get manifest sonarqube
kubectl -n sonarqube get pvc
```

Redact Secrets before storing output. A Helm release history and a PVC snapshot do not replace the external database backup. Confirm that volume snapshots are application-consistent and restorable in the chosen storage system.

## Upgrade workflow

Use this order for native, Docker, and Kubernetes deployments:

1. Identify the current product, edition, version, Java version, database version, and plugins.
2. Read the SonarSource release notes and determine the supported update path. Do not skip mandatory intermediate versions.
3. Verify the target platform, Java, database, image, chart, and Kubernetes compatibility.
4. Check every plugin against the target release; remove abandoned or incompatible plugins before the maintenance window.
5. Announce a maintenance window and pause new analysis submissions.
6. Allow in-progress compute-engine tasks to finish, then stop the application cleanly.
7. Create the database backup and all method-specific records listed above.
8. Restore the backup in isolation and verify it, or verify a recent rehearsed restore with the same method.
9. Stage the pinned target binaries, image, or chart without deleting the previous version.
10. Start the target and allow any database migration to complete without interruption.
11. Wait for `/api/system/status` to report `UP`.
12. Validate login, permissions, integrations, background tasks, plugins, and a sample scan.
13. Monitor errors, queues, database performance, and storage through the agreed observation period.

Community Build `26.7.0.124771`, Server latest `2026.3.1`, and Server LTA `2026.1.3` are independent pinned channels. The Kubernetes package uses published chart `2026.3.1`, whose Server `appVersion` is also `2026.3.1`; chart versions and application versions are still distinct compatibility pins. Moving between product families or editions is not the same as a routine patch update; follow the exact upstream migration rules.

## Rollback

An application-only rollback is unsafe after a database migration. The high-level rollback is:

1. Stop the failed target version.
2. Restore the database backup taken immediately before the upgrade.
3. Restore the previous application version, image, chart values, plugins, and configuration.
4. Start the previous version.
5. Verify system status, login, background tasks, integrations, and a sample scan.

For Kubernetes, `helm rollback` alone does not restore a migrated database. For Docker, changing an image tag alone does not restore it either. Do not promise a rollback unless the matching database restore has been tested.

## Recovery validation

A recovery exercise should prove:

- The restored database is readable by the matching SonarQube version.
- Required encryption keys, certificates, plugins, and trust stores are available.
- Authentication and DevOps integrations behave as expected.
- A new scan can be submitted and processed.
- Recovery time and recovery point objectives are met.
- Operators can recover without undocumented credentials or a single person's workstation.

Schedule restore drills and record their date, duration, result, and follow-up actions.
