# Operations Guide

Day-2 operations for a running deployment. Written to be executable at 03:00 by someone who did not
build the system.

---

## Topology at a glance

```
Internet ──:80──▶ Nginx (host) ──127.0.0.1:8080──▶ Podman container ──:5432──▶ RDS PostgreSQL
                                                    (systemd: employee-api)
```

Everything runs on one EC2 instance in the public subnet with an Elastic IP. The database is in
private subnets and is reachable only from the instance's security group.

| Thing | Where |
|---|---|
| Application service | `systemctl status employee-api` |
| Container | `podman ps` (name: `employee-api`) |
| Reverse proxy | `systemctl status nginx` |
| App config | `/opt/employee-api/config/app.env` (mode 0640) |
| Nginx site | `/etc/nginx/sites-available/employee-api` |
| Nginx logs | `/var/log/nginx/employee-api.{access,error}.log` |
| App logs | `journalctl -u employee-api` |
| CloudWatch | Log groups `/<project>/application`, `/<project>/nginx/access`, `/<project>/nginx/error` |

---

## First response: is it up?

```bash
# From anywhere
curl -s http://<host>/actuator/health

# On the instance
sudo systemctl is-active employee-api nginx
sudo podman ps
```

`/actuator/health` returning `{"status":"UP"}` means the app is running **and** the database is
reachable. That single check rules out most of the stack.

---

## Diagnosing by symptom

### 502 Bad Gateway from Nginx

Nginx is up; the application behind it is not.

```bash
sudo systemctl status employee-api      # is the unit running?
sudo podman ps -a                       # did the container exit?
sudo journalctl -u employee-api -n 100 --no-pager
```

Most common causes, in order:

1. **The container crashed on startup** — usually a database connection failure. Check the log for
   `Connection refused` or `FATAL: password authentication failed`.
2. **The image failed to pull** — GHCR authentication expired or the package is private.
3. **The app is still booting** — Spring Boot with Flyway takes 30–60 seconds on a `t3.small`.
   `HEALTHCHECK` has a 60-second start period for this reason.

```bash
sudo systemctl restart employee-api
sudo journalctl -u employee-api -f
```

### Health endpoint reports `DOWN`

The application is running but a health indicator is failing — nearly always the database.

```bash
# Can the host reach RDS at all?
DB_HOST=$(sudo grep '^DB_HOST=' /opt/employee-api/config/app.env | cut -d= -f2)
nc -zv "$DB_HOST" 5432
```

- **Connection refused / timeout** → the database security group is not allowing the app security
  group on 5432, or the RDS instance is rebooting/failed over. Check the RDS console.
- **Connects but auth fails** → `DB_PASSWORD` in the repository secret no longer matches the RDS
  master password. Re-run the deploy; do not edit the file by hand, Chef will overwrite it.

### Connection refused on port 80

Nginx itself is down or misconfigured.

```bash
sudo nginx -t                    # config syntax
sudo systemctl status nginx
sudo tail -50 /var/log/nginx/employee-api.error.log
```

If `nginx -t` fails after a converge, the Chef template rendered something invalid — check
`/etc/nginx/sites-available/employee-api` and re-run the configure stage.

### Slow responses / p95 breaching 500 ms

```bash
# Resource pressure
top -bn1 | head -20
free -m
df -h

# Is the database the bottleneck?
sudo journalctl -u employee-api | grep -i 'slow\|timeout'
```

RDS logs statements slower than 1 second (`log_min_duration_statement=1000`) — check the
`/aws/rds/instance/<project>-db/postgresql` log group in CloudWatch.

A `t3.small` with a `db.t3.micro` is sized for modest load. Sustained CPU credit exhaustion on
either shows up as a gradual latency climb; the `<project>-db-cpu` alarm covers the database side.

---

## Routine operations

### Restart the application

```bash
sudo systemctl restart employee-api
curl -s http://localhost/actuator/health
```

### View live logs

```bash
sudo journalctl -u employee-api -f              # application
sudo tail -f /var/log/nginx/employee-api.access.log   # requests
```

### Re-run configuration

Configuration is idempotent — re-running the `configure` stage of `deploy.yml` converges the host
back to its declared state. Prefer this over editing files on the box: **any manual edit to
`/opt/employee-api/config/app.env`, the systemd unit, or the Nginx site is overwritten on the next
converge.**

### Deploy a new version

Push to `main` and run `deploy.yml`. Never build or push images from the instance.

### Rotate the admin password

1. Update the `API_ADMIN_PASSWORD` repository secret (alphanumeric, ≥ 20 chars).
2. Re-run `deploy.yml` — Chef re-renders `app.env` and restarts the service.

### Rotate the database password

1. Change the master password on the RDS instance.
2. Update the `DB_PASSWORD` secret to match.
3. Re-run `deploy.yml`.

Doing these in the wrong order causes an outage: the app restarts with the new password before RDS
accepts it.

---

## Log rotation

Managed by `/etc/logrotate.d/employee-api`: daily, 14 rotations, compressed, `copytruncate`.
Container logs go to journald and are bounded by the system journal's own limits.

If the disk fills anyway, the usual culprit is unreaped container images:

```bash
sudo podman image prune -a
```

---

## Monitoring

CloudWatch collects CPU, memory and disk from the agent, plus the three log groups. Two alarms
exist:

| Alarm | Fires when |
|---|---|
| `<project>-instance-status` | EC2 status check fails 3× in 3 minutes |
| `<project>-db-cpu` | RDS CPU > 80% for 10 minutes |

**Neither alarm notifies anyone** — they have no `alarm_actions`. They are visible in the console
and via the API only. Wiring an SNS topic is listed as an optional enhancement in the deployment
guide, and should be the first thing added if this system gets real users.

---

## Backups

RDS automated backups run daily in the 03:00–04:00 UTC window with **7-day retention**.

- **Point-in-time restore** is available within that window through the RDS console.
- **There is no final snapshot on teardown** — `skip_final_snapshot = true`. Take a manual snapshot
  before running `destroy.yml` if the data matters.
- Backups have not been restore-tested. A restore drill is the correct next step before this holds
  anything important.

---

## Escalation

| Situation | Action |
|---|---|
| Instance unreachable, status check failing | Reboot from the EC2 console; if it recurs, re-run `deploy.yml` to rebuild |
| RDS unavailable | Check the RDS console for maintenance/failover; single-AZ means a maintenance restart is a brief outage |
| Repeated deploy failures | Read the first error in the failing stage's log — later errors cascade |
| Suspected compromise | Detach the instance's security group ingress, snapshot the volume, then investigate |
