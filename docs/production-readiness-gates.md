# Production acceptance gates

Do not describe an installation as production-ready until every applicable gate
below has recorded evidence. A successful install, rendered chart, or green
static check is necessary but not sufficient.

| Gate | Required evidence | Owner |
|---|---|---|
| Release integrity | Reviewed pins/digests, CI green, and no unresolved critical deployment-tooling finding | Release owner |
| Runtime validation | Green Docker and Kubernetes integration jobs for the exact revision | Release owner |
| Database recovery | A restore of the intended database backup into an isolated environment, with date, duration, and result recorded | Database owner |
| Network and TLS | Verified HTTPS endpoint, valid certificate chain, restrictive ingress and egress policy, and documented approved external flows | Platform owner |
| Identity and secrets | Initial administrator replaced, approved authentication configured, secret rotation owner and schedule recorded | Security owner |
| Monitoring | Health, queue, JVM, database latency, disk, certificate, backup-age, and restore-age alerts tested end to end; production Kubernetes monitoring namespace recorded | Operations owner |
| Capacity and resilience | Measured load test or sizing review, database recovery objectives, storage failure behavior, and disruption procedure approved | Service owner |
| Change control | Upgrade runbook rehearsed for the exact edition/version and rollback boundary understood after database migration | Release and database owners |

## Evidence record

For each production environment, record the revision, SonarQube edition and
version, image/chart digests, database version, test date, approver, result,
and links to the redacted CI, monitoring, and restore evidence. Store that
record in the organisation's approved change-management system, not in this
repository if it contains infrastructure details.

The toolkit can automate deployment checks, but it cannot truthfully certify
these environment-specific gates without that operational evidence.
