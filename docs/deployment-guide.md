# Deployment Guide

How to take this repository from nothing to a running deployment, verify it, and roll it back.

---

## 1. Prerequisites

| Requirement | Detail |
|---|---|
| AWS account | With permission to create VPC, EC2, RDS, IAM, ECR, CloudWatch resources |
| GitHub repository | With Actions enabled. **No package permissions needed** — images go to ECR |
| Region | `us-east-1` (change `aws_region` in `infra/variables.tf` and the pipeline spec together) |
| Quotas | 1 VPC, 1 Elastic IP, 1 EC2 instance, 1 RDS instance |

### Required repository secrets

Supplied by the platform at deploy time:

| Secret | Purpose |
|---|---|
| `PROJECT_NAME` | Resource name prefix, and the ECR repository name |
| `TF_STATE_BUCKET` | Terraform state bucket |
| `SSH_USER` | Login user — `ubuntu` for this AMI |
| `SSH_PRIVATE_KEY` / `SSH_PUBLIC_KEY` | Project keypair |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Cloud credentials — also used for the ECR push |

Set for this project before the first deploy:

| Secret | Constraints |
|---|---|
| `DB_PASSWORD` | Alphanumeric, ≥ 20 characters. **No** `% $ / : @ # ? '` — they break connection URLs and shell interpolation |
| `API_ADMIN_PASSWORD` | Alphanumeric, ≥ 20 characters |

---

## 2. Deployment order

The workflows are independent, but the first deployment has a required order because each stage
consumes the previous one's output.

### Option A — one shot (recommended)

Run **`deploy.yml`**. It provisions infrastructure and deploys the application in one pass:

```
build → quality gates → tests → Semgrep → Podman build → Clair scan → ECR push
      → Terraform apply → Chef converge → verify
```

### Option B — infrastructure first

1. Run **`infrastructure.yml`** — creates the AWS resources and prints the application URL.
2. Run **`deploy.yml`** — Terraform converges (no changes), then Chef configures and deploys.

Both are safe to re-run. Terraform state lives in the platform's bucket under
`<PROJECT_NAME>/terraform.tfstate`, so a retry always finds the previous attempt's state and
reconciles rather than duplicating resources.

### After deployment

Run **`validation.yml`** to prove the deployment works: smoke test, REST Assured, Newman, and a k6
load test that enforces p95 < 500 ms and error rate < 1%.

---

## 3. What gets created

| Resource | Detail | Approx. monthly cost |
|---|---|---|
| VPC + subnets + IGW + route tables | `10.20.0.0/16`, one public + two private | $0 |
| EC2 instance | `t3.small`, Ubuntu 22.04, 20 GB gp3 encrypted | ~$15 |
| Elastic IP | Static public address | $0 while attached |
| RDS PostgreSQL 16 | `db.t3.micro`, 20 GB gp3, single-AZ, 7-day backups | ~$15–18 |
| ECR repository | Scan-on-push, keeps 10 most recent images | ~$1 |
| IAM role + instance profile | CloudWatch agent, SSM, ECR pull | $0 |
| CloudWatch | 3 log groups (14-day retention), 2 alarms | ~$2–5 |

**Total: roughly $45–60/month.** There is deliberately no NAT gateway (saves ~$33/month) — the
instance sits in the public subnet with an Elastic IP.

---

## 4. Verification

The `verify` stage does this automatically, but to check by hand:

```bash
HOST=$(cd infra && terraform output -raw instance_public_ip)

# 1. Health — should report UP
curl -s "http://$HOST/actuator/health"

# 2. Authentication — should be 401
curl -s -o /dev/null -w '%{http_code}\n' "http://$HOST/api/v1/employees"

# 3. Authenticated read — should be 200
curl -s -u admin:$API_ADMIN_PASSWORD "http://$HOST/api/v1/employees"

# 4. Landing page in a browser
open "http://$HOST"
```

A healthy `/actuator/health` proves the application is up **and** that it can reach RDS — the
database health indicator is part of that response.

---

## 5. Rollback

The pipeline's rollback strategy is `rerun`.

**Application rollback** — every image is tagged with its commit SHA in ECR. To go back to a
previous version, re-run `deploy.yml` from the earlier commit, or on the host:

```bash
REPO=$(cd infra && terraform output -raw ecr_repository_url)
REGISTRY="${REPO%%/*}"
aws ecr get-login-password --region us-east-1 \
  | sudo podman login --username AWS --password-stdin "$REGISTRY"
sudo podman pull "$REPO:<previous-sha>"
# edit the image reference in /etc/systemd/system/employee-api.service
sudo systemctl daemon-reload && sudo systemctl restart employee-api
```

The manual edit is overwritten by the next Chef converge — use it only as an emergency stop-gap and
follow up with a real redeploy from the intended commit.

**Infrastructure rollback** — revert the commit that changed `infra/` and re-run. Applying the
previous Terraform configuration *is* the rollback.

**Full teardown** — run `destroy.yml`. This destroys everything including the database and the ECR
repository (`force_delete = true`, so images do not block teardown).
`skip_final_snapshot = true`, so **there is no final database snapshot**. Take one manually first if
the data matters.

---

## 6. Common first-deploy failures

| Symptom | Cause | Fix |
|---|---|---|
| `terraform init` fails on the backend | State bucket secret missing | Confirm `TF_STATE_BUCKET` is set |
| `Permission denied (publickey)` | `SSH_USER` doesn't match the AMI | Must be `ubuntu` for Ubuntu 22.04 |
| `RepositoryAlreadyExistsException` on apply | The ECR import step was skipped | `scripts/import-ecr-repo.sh` must run after `terraform init` in the provision stage |
| Chef fails pulling the image | Instance profile missing ECR pull rights | Check `aws_iam_role_policy.app_ecr_pull` is attached |
| Health check times out | App can't reach RDS | Check the DB security group allows the app SG on 5432 |
| Clair stage times out | First-run vulnerability DB load | Expected on run one; the stage allows 45 min |
| Clair fails on HIGH/CRITICAL | Real CVEs in dependencies | **Upgrade the dependency.** Do not weaken the gate |
| DB connection errors with odd parsing | Password contains URL-special characters | Regenerate as alphanumeric only |

---

## 7. Optional enhancements

Deliberately excluded from this tier — each is a real change, not a toggle:

- **TLS/HTTPS** — needs a domain. Add Route 53 + ACM with an ALB, or certbot on the instance.
- **Load balancer + autoscaling** — replace the Elastic IP with an ALB and an autoscaling group.
- **Multi-AZ RDS** — set `multi_az = true` in `infra/database.tf`; roughly doubles the database cost.
- **Alert delivery** — the CloudWatch alarms exist but have no `alarm_actions`; add an SNS topic.
- **Deletion protection** — set `deletion_protection = true` and `skip_final_snapshot = false` on the
  RDS instance once the data matters.
- **Image immutability** — set the ECR repository to `IMMUTABLE` tags once the deploy cadence is
  stable, so a tag can never silently point at different content.
