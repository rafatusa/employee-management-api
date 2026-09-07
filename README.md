# Employee Management API

A production REST API for an employee directory: **Spring Boot 3.2** on **Java 21**, packaged as a
**Podman** container, deployed to **AWS EC2** behind **Nginx**, backed by **PostgreSQL 16 on RDS**,
provisioned with **Terraform** and configured with **Chef**.

```
Client ──HTTP :80──▶ Nginx ──proxy_pass──▶ Podman container :8080 ──JDBC :5432──▶ RDS PostgreSQL
                     └──────────── EC2 (Ubuntu 22.04, Elastic IP) ─────────────┘
```

---

## Contents

| Document | Purpose |
|---|---|
| `README.md` | This file — overview, local development, workflows |
| `docs/deployment-guide.md` | How to deploy from scratch, verify, and roll back |
| `docs/operations-guide.md` | Day-2 operations: logs, restarts, common failures |
| `docs/api.md` | Full API reference |
| `docs/architecture.md` | Architecture and CI/CD diagrams with rationale |
| `.udap/architecture.d2` | Architecture source of truth (D2) |

---

## API

All endpoints require HTTP Basic authentication except `/actuator/health` and the landing page.
Writes require the `ADMIN` role.

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/employees` | List employees (`?department=` filter) |
| `GET` | `/api/v1/employees/{id}` | Fetch one employee |
| `POST` | `/api/v1/employees` | Create an employee |
| `PUT` | `/api/v1/employees/{id}` | Replace an employee |
| `DELETE` | `/api/v1/employees/{id}` | Delete an employee |
| `GET` | `/actuator/health` | Liveness + database health |

```bash
curl -u admin:$API_ADMIN_PASSWORD http://<host>/api/v1/employees
```

See `docs/api.md` for payload schemas and error responses.

---

## Local development

Requires JDK 21 and a PostgreSQL 16 instance (or Podman to run one).

```bash
# 1. Start a database
podman run -d --name employees-db -p 5432:5432 \
  -e POSTGRES_USER=employees -e POSTGRES_PASSWORD=localdev \
  -e POSTGRES_DB=employees docker.io/library/postgres:16-alpine

# 2. Configure the app
cp .env.example .env      # then edit it

# 3. Run
export $(grep -v '^#' .env | xargs)
gradle bootRun
```

The app is then on <http://localhost:8080>.

> **Gradle wrapper:** this repository does not ship `gradlew`. CI provisions a pinned Gradle 8.10.2
> through `gradle/actions/setup-gradle`, so the build is reproducible without committing a binary
> wrapper JAR. Locally, use a Gradle 8.10.x installation (`sdk install gradle 8.10.2`).

### Quality gates

```bash
gradle checkstyleMain pmdMain spotbugsMain     # static analysis
gradle test jacocoTestReport jacocoTestCoverageVerification   # tests + 90% coverage gate
```

The coverage gate is set at **90% line coverage** and is enforced in CI. It is not a suggestion —
if it fails, add tests.

---

## The three workflows

Each is independently runnable from the Actions tab.

### 1. `infrastructure.yml` — provision AWS

Terraform `fmt` → `validate` → `plan` → `apply` → verify. Creates the VPC, public subnet, internet
gateway, security groups, EC2 instance, Elastic IP, RDS PostgreSQL, IAM role and CloudWatch log
groups. Safe to re-run: it converges to the declared state.

### 2. `deploy.yml` — build, scan, deploy

The full application path:

```
Gradle build → Checkstyle ┐
                PMD       ├→ JUnit + JaCoCo(90%) → Semgrep → Podman build
                SpotBugs  ┘                                       ↓
                                                            Clair scan
                                                                  ↓
                                                             Push GHCR
                                                                  ↓
                              Terraform provision → Chef configure → Verify
```

**Container scanning uses genuine Clair**, not a lighter substitute. Clair is a server, so the job
stands up a local registry, a PostgreSQL instance and Clair v4.7.4 in `combo` mode, then drives the
scan with `clairctl` and fails on HIGH/CRITICAL findings. This adds roughly 2–3 minutes per run, and
the first run is slower while Clair loads its vulnerability database.

### 3. `validation.yml` — validate the deployment

Smoke test → REST Assured integration tests → Postman/Newman functional tests → k6 load test →
consolidated HTML report → published artifacts.

Verifies application health, authentication, employee CRUD, database connectivity, the Nginx reverse
proxy, **p95 < 500 ms** and **error rate < 1%** (enforced as k6 thresholds — the job fails if either
budget is exceeded).

A fourth workflow, `destroy.yml`, is rendered automatically for teardown.

---

## Repository layout

```
├── src/main/java/...           Application code
├── src/test/java/...           Unit tests (JUnit 5, 90% coverage gate)
├── src/integrationTest/java/   REST Assured tests against a deployed instance
├── infra/                      Terraform (VPC, EC2, RDS, IAM, CloudWatch)
├── chef/
│   ├── cookbooks/employee_api/ Java 21, Podman, Nginx, CloudWatch agent, systemd
│   ├── nodes/                  Node attributes rendered at deploy time (gitignored)
│   └── solo.rb                 chef-solo configuration
├── scripts/                    Clair orchestration, Chef bootstrap, reporting
├── tests/postman/              Newman functional collection
├── tests/k6/                   Load test with p95 / error-rate thresholds
├── config/                     Checkstyle, PMD, SpotBugs rules
├── docs/                       Deployment, operations, API, architecture
└── .udap/                      Architecture source + pipeline spec
```

---

## Configuration

The application reads everything from the environment. In deployed environments Chef renders these
into `/opt/employee-api/config/app.env` (mode `0640`) from Terraform outputs and repository secrets.

| Variable | Description |
|---|---|
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` | PostgreSQL connection — from Terraform outputs |
| `DB_PASSWORD` | Database password — repository secret |
| `API_ADMIN_USERNAME`, `API_ADMIN_PASSWORD` | API admin credentials — repository secret |
| `SERVER_PORT` | Application port (default `8080`, bound to loopback) |

### Repository secrets

Provided by the platform: `PROJECT_NAME`, `TF_STATE_BUCKET`, `SSH_USER`, `SSH_PRIVATE_KEY`,
`SSH_PUBLIC_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `GITHUB_TOKEN`.

Set for this project: `DB_PASSWORD`, `API_ADMIN_PASSWORD`.

---

## Security posture

- The database has **no public route** — it sits in private subnets with a security group that
  accepts traffic only from the application's security group on port 5432.
- The instance exposes **only ports 80 and 22**. The application itself binds `127.0.0.1:8080`, so
  it is unreachable except through Nginx.
- The container runs as an **unprivileged user**, storage is encrypted, and **IMDSv2 is required**.
- Credentials never touch the instance as files in the repository: Chef renders them at converge
  time and the node attribute file is shredded afterwards.

### Not included (deliberate)

TLS/HTTPS is **not** configured — the requirement was reachability over the EC2 public IP, and
certificates need a domain. Also out of scope at this tier: load balancer + autoscaling, Multi-AZ
RDS, and alert delivery (CloudWatch alarms exist but publish to no SNS topic). See the deployment
guide for how to add them.
