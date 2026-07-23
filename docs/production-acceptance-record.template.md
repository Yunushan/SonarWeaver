# Production acceptance record template

Copy this template into the organisation's approved change-management system
for each environment. Do not commit completed records to this repository: they
can reveal internal topology, service names, ticket references, or operational
evidence. Do not include credentials, passcodes, unredacted logs, database
dumps, private keys, or certificate private material.

## Change identity

| Field | Value |
|---|---|
| Change / release ID | |
| Environment | |
| Planned maintenance window | |
| Service owner | |
| Platform owner | |
| Database owner | |
| Security approver | |
| SonarWeaver revision | |
| Deployment method | Native Linux / Native Windows / Native macOS / Docker / RKE2 / K3s |
| SonarQube edition and version | |
| Chart version and image digests, if used | |
| Database engine and version | |

## Required evidence

Record a redacted URL, ticket ID, dashboard reference, or evidence-store object
for every applicable item. A blank field means the production gate is not
accepted.

| Gate | Evidence reference | Date/time (UTC) | Result | Owner / approver |
|---|---|---|---|---|
| Release integrity: reviewed pins/digests, green CI, deployment-tooling vulnerability disposition | | | Pass / fail | |
| Delivery governance: protected default branch, required checks/reviews, blocked force-push/deletion, Dependabot alerts/updates, Actions SHA-pinning enforcement | | | Pass / fail | |
| Runtime validation: Docker/Kubernetes integration result for the deployed revision | | | Pass / fail / N/A | |
| Database recovery: isolated restore date, duration, result, RPO/RTO comparison | | | Pass / fail | |
| Network and TLS: HTTPS, certificate chain, ingress/egress policy, approved external flows | | | Pass / fail | |
| Identity and secrets: initial administrator replaced, authentication configured, rotation owner/schedule | | | Pass / fail | |
| Monitoring: health, queue, JVM, database, disk, certificate, backup-age, restore-age alerts exercised | | | Pass / fail | |
| Capacity and resilience: sizing/load review, storage failure behaviour, disruption procedure | | | Pass / fail | |
| Change control: exact upgrade path rehearsed, rollback boundary understood | | | Pass / fail | |

## Upgrade and recovery checkpoint

- Backup identifier, encryption/key-management reference, and retention policy: 
- Isolated restore target (redacted): 
- Restore started/completed (UTC) and measured duration: 
- Matching SonarQube version used to validate restored data: 
- Rollback decision point after database migration: 
- Explicit upgrade acknowledgements used, if applicable: 

## Post-deployment verification

- HTTPS health check reference (`/api/system/status` reports `UP`): 
- Authenticated monitoring check reference: 
- Login, permissions, integration, plugin, and sample-scan validation reference: 
- Observation period, alerts reviewed, and outcome: 

## Final decision

| Decision | Time (UTC) | Approver | Notes |
|---|---|---|---|
| Accept production traffic / reject / defer | | | |
