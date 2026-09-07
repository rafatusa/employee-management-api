# Architecture

The authoritative source is [`.udap/architecture.d2`](../.udap/architecture.d2). This document
explains the reasoning behind it.

---

## System architecture

```
                          ┌─────────────────────────────┐
   Developer / Client ────▶  Internet Gateway (VPC)      │
                          │  10.20.0.0/16               │
                          └──────────────┬──────────────┘
                                         │
                    ┌────────────────────▼─────────────────────┐
                    │  Public subnet 10.20.1.0/24              │
                    │                                          │
                    │   Elastic IP                             │
                    │        │                                 │
                    │        ▼                                 │
                    │   EC2 t3.small (Ubuntu 22.04)            │
                    │    ├── Nginx           :80  ◀── public   │
                    │    └── Podman container :8080 (loopback) │
                    └────────────────────┬─────────────────────┘
                                         │ JDBC :5432
                    ┌────────────────────▼─────────────────────┐
                    │  Private DB subnets                      │
                    │  10.20.11.0/24 + 10.20.12.0/24           │
                    │                                          │
                    │   RDS PostgreSQL 16 (db.t3.micro)        │
                    └──────────────────────────────────────────┘

   GitHub Actions ──build──▶ GHCR ──pull──▶ EC2
   GitHub Actions ──chef-solo over SSH──▶ EC2
   EC2 + RDS ──logs & metrics──▶ CloudWatch
```

### Why this shape

**Dedicated VPC rather than the default.** Explicitly requested. The account had 3 of 5 VPCs in use,
so there was headroom. It also makes the private database placement real rather than nominal — the
default VPC has no private subnets.

**No NAT gateway.** The application instance is in the public subnet with an Elastic IP, so it has
direct outbound access for package and image pulls. The database subnets need no egress at all. A
NAT gateway would add roughly $33/month and buy nothing here.

**Two database subnets for a single-AZ database.** RDS requires a subnet group spanning at least two
availability zones even when the instance itself is single-AZ. This also means enabling Multi-AZ
later is a one-line change.

**Nginx in front of the application.** The container binds `127.0.0.1:8080` and is unreachable from
outside the host. Nginx owns port 80. This keeps the public surface to one process, gives a place to
terminate TLS when a domain exists, and means the application never has to care about proxy
concerns.

**Elastic IP rather than the instance's ephemeral address.** The verify and validation workflows
resolve the host from a Terraform output; an ephemeral IP would change on every stop/start and
invalidate anything cached against it.

**Security groups reference each other, not CIDRs.** The database group accepts port 5432 from the
application's security group by ID. There is no CIDR-based database rule anywhere, so the database
cannot be accidentally exposed by a subnet change.

---

## CI/CD pipeline

Three independently runnable workflows, plus an auto-generated teardown workflow.

### `deploy.yml` — build and deploy

```
              ┌──▶ Checkstyle ──┐
Gradle build ─┼──▶ PMD ─────────┼──▶ JUnit + JaCoCo (90%) ──▶ Semgrep SAST
              └──▶ SpotBugs ────┘                                  │
                                                                   ▼
                                                        Podman build image
                                                                   │
                                                                   ▼
                                            local registry + Postgres + Clair
                                                    clairctl report
                                                    fail on HIGH/CRITICAL
                                                                   │
                                                                   ▼
                                                          Push to GHCR
                                                                   │
                                                                   ▼
                       Terraform provision ──▶ Chef configure ──▶ Verify
```

The three static-analysis stages run in parallel — they are independent and each fails fast on its
own.

**Clair is genuine, not substituted.** Clair v4 is a Postgres-backed server, not a CLI, so the scan
stage stands up the whole thing inside the job: a `registry:2` container (Clair's indexer fetches
layers over the registry API and cannot read Podman's local image store), a `postgres:15-alpine`
container as its datastore, and Clair itself in `combo` mode. `clairctl` produces a JSON report and
`scripts/clair-gate.py` fails the build on HIGH/CRITICAL findings.

Cost of that choice: 2–3 minutes per run, and a notably slower first run while Clair loads its
vulnerability database. The stage timeout is 45 minutes to absorb it.

### `infrastructure.yml` — Terraform only

`fmt` → `validate` → `plan` → `apply` → verify. Useful for infrastructure changes that do not need
an application rebuild, and for confirming the account state before a first deploy.

### `validation.yml` — post-deployment validation

Smoke test → REST Assured → Newman → k6 → consolidated HTML report → published artifacts.

The k6 thresholds (`p(95)<500`, `http_req_failed<0.01`) are enforced, not advisory: k6 exits
non-zero when a threshold is breached, which fails the job.

---

## Key design decisions

| Decision | Rationale | Trade-off accepted |
|---|---|---|
| Chef instead of Ansible | Explicitly requested. `chef-solo` (`chef-client --local-mode`) over SSH — no Chef Server, no extra infrastructure | Diverges from the platform's default configure mechanism |
| Podman instead of Docker | Explicitly requested. Daemonless and rootless-capable; systemd manages the container lifecycle directly | Smaller ecosystem; some tooling assumes a Docker socket |
| Genuine Clair over Trivy | Explicitly requested after Trivy was proposed | Slower, more moving parts in the job, more failure surface |
| Flyway owns the schema | `ddl-auto: validate` — Hibernate never alters the database. Migrations are reviewable and ordered | A schema change requires a migration file, not just an entity edit |
| HTTP Basic auth | Sufficient for an internal directory API; no token infrastructure to operate | Not appropriate for public/multi-tenant use — needs OAuth2/OIDC |
| 90% coverage gate | Requested, and enforced in CI | Genuinely constrains what can be merged; the correct response to a failure is more tests |
| No TLS | Requirement was reachability via the EC2 public IP; certificates need a domain | Traffic is unencrypted — must be fixed before real use |

---

## Data flow: a request

1. Client sends `GET /api/v1/employees` to the Elastic IP on port 80.
2. Nginx accepts it, adds `X-Forwarded-*` headers, proxies to `127.0.0.1:8080`.
3. Spring Security checks HTTP Basic credentials — `401` if absent or wrong.
4. `EmployeeController` delegates to `EmployeeService`.
5. `EmployeeService` queries through `EmployeeRepository` (JPA/Hibernate).
6. HikariCP uses a pooled connection to RDS over port 5432 within the VPC.
7. Rows map to `EmployeeResponse` records and serialise to JSON.
8. Nginx logs the request; the CloudWatch agent ships the log line.

---

## Known limitations

- **Single instance, single AZ.** Any instance failure is an outage. No autoscaling, no load
  balancer.
- **Single-AZ database.** RDS maintenance or failover is a brief outage.
- **No TLS.** Credentials cross the network in Base64 over plain HTTP. This is the most important
  thing to fix.
- **Alarms notify nobody.** They exist and evaluate, but have no SNS destination.
- **Backups are untested.** Automated daily backups with 7-day retention exist; no restore drill has
  been performed.
- **SSH open to `0.0.0.0/0`.** Required for the Chef configure stage from GitHub-hosted runners,
  whose IP ranges are wide. Restricting this means either self-hosted runners or SSM-based
  configuration.
