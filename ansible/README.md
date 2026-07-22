# Ansible production path

This optional layer deploys a single, native Linux SonarQube instance through
systemd. It is intended for managed VM or bare-metal fleets; it does not
replace SonarWeaver's CLI for local use or Helm/GitOps for Kubernetes.

## Scope and safety boundaries

- Production only: an external JDBC database and a protected password file are
  mandatory. Evaluation/H2 installs are intentionally unavailable here.
- The default pin mirrors `config/versions.env`; CI checks that it remains in
  sync. Set `sonarweaver_edition` for recordkeeping and select the matching
  pinned `sonarweaver_version`.
- The role never creates, copies, prints, or stores a database password. It
  reads only an existing protected file on the managed host.
- An upgrade stops before activation, requiring `sonarweaver_upgrade_approved`
  and `sonarweaver_backup_verified` after the documented maintenance and
  restore checks have occurred. New installations do not need these assertions.
- The standard native deployment is one application node. It is not an
  active-active Enterprise or Data Center architecture.

## Run it

Install the required collections on the control host:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

The collection and CI validator versions are intentionally exact locks. Update
them only with the related Ansible syntax/lint and staging-deployment checks.

Copy `ansible/inventory/production.example.yml` to a protected location and
create a similarly protected variables file. Do not place secrets in Git. The
database password file referenced below must already exist on every target and
be accessible only to the intended service/automation identities.

```yaml
sonarweaver_edition: server-lta
sonarweaver_version: "2026.1.3"
sonarweaver_jdbc_url: "jdbc:postgresql://db.example.internal:5432/sonarqube"
sonarweaver_jdbc_user: sonarqube
sonarweaver_jdbc_password_file: /run/secrets/sonarqube-jdbc-password

sonarweaver_proxy_enabled: true
sonarweaver_proxy_server_name: sonar.example.internal
sonarweaver_proxy_tls_certificate: /etc/pki/tls/certs/sonar.example.internal.crt
sonarweaver_proxy_tls_certificate_key: /etc/pki/tls/private/sonar.example.internal.key
```

Run from the repository root:

```bash
ansible-playbook -i /secure/inventory.yml ansible/playbooks/site.yml
```

The first run validates Java, creates the service identity and persistent
directories, applies the required kernel limits, stages the pinned native
installer, installs the release without starting it, renders the optional TLS
proxy, validates its certificate/key paths and `nginx -t`, then starts
SonarQube and waits for `/api/system/status` to return `UP`.

## Secrets

Supply connection secrets through a protected host file, Ansible Vault, or a
lookup plugin for the organisation's secret manager. If a lookup plugin
materialises a password file, make it `0640` or stricter and clean it up using
that secret-manager workflow. Never set `sonarweaver_jdbc_password` as an
inventory variable; this role intentionally has no such option.

## Upgrades and rollback

Read [the upgrade procedure](../docs/backup-upgrade.md) before changing
`sonarweaver_version`. Complete the maintenance window, database backup, and
restore validation first, then set these values for that one run:

```yaml
sonarweaver_upgrade_approved: true
sonarweaver_backup_verified: true
```

The installer retains versioned binaries under `/opt/sonarqube/versions`; a
database migration still makes an application-only rollback unsafe. Restore
the matching database backup before returning the `current` symlink to an older
release.

## Kubernetes

Use the existing Helm chart workflow with GitOps (such as Argo CD or Flux) for
RKE2/K3s application state. Ansible may prepare node limits or supporting VM
infrastructure, but it should not compete with Helm/GitOps for ownership of a
Kubernetes release.

## Validation

The repository CI runs YAML linting, `ansible-lint`, Ansible playbook syntax
checks, and the Molecule scenario syntax sequence. These checks validate the
automation structure; run an approved staging deployment before production.
