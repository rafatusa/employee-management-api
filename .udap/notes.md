# employee-management-api — working notes

## Context
Spring Boot 3.2 / Java 21 / Gradle Employee Management REST API on AWS EC2 (us-east-1),
Podman container fronted by Nginx, PostgreSQL RDS, configured by Chef, CI on GitHub Actions.

## Status
- [x] discovery, meta approved
- [x] architecture.d2 (rev 1), pipeline.yaml (rev 5)
- [x] design gate APPROVED, plan gate APPROVED (2026-09-07)
- [x] generation complete (67 files)
- [x] validate_project PASS (incl. real `terraform validate`)
- [~] test_project — compile PASSES; blocked at checkstyle by a SANDBOX limit (see below)
- [ ] push / secrets / deploy  <-- NEXT, awaiting user decision

## Rehearsal outcome (read this before re-running test_project)
`test_project` catches real bugs up to the point where Gradle forks a Worker Daemon, then
dies on the sandbox's thread limit:
    pthread_create failed (EAGAIN) ... unable to create native thread
compileJava + compileTestJava PASS (16s). checkstyleMain/Test fail forking a 2nd JVM.
This is UDAP's server, NOT the project. GitHub runners fork worker daemons routinely.
**DO NOT** disable checkstyle/pmd/spotbugs, set ignoreFailures, or swap the Gradle plugins
for raw CLI calls to turn this green — platform rule 9 / rule 4.

## REAL defects the rehearsal caught (fixed — do not regress)
1. `spotbugs { reportLevel = ...Confidence.MEDIUM }` -> Groovy DSL resolves the bare qualified
   name to the enum **Class**. Must be `Confidence.valueOf('MEDIUM')` / `Effort.valueOf('MAX')`.
2. `org.flywaydb:flyway-database-postgresql` is NOT in Spring Boot 3.2's BOM (arrived with
   Boot 3.3 / Flyway 10) -> resolved to empty version, failed compileJava. Boot 3.2 manages
   Flyway 9.x where PostgreSQL support is inside `flyway-core`. Removed the module.

## Defects found by inspection during generation (fixed)
3. **Scaffold shipped Spring Boot 4.1.1 with invented starters** (`spring-boot-starter-webmvc`,
   `-actuator-test`, `-data-jpa-test` do not exist). Rewrote to Boot 3.2.10, real coordinates.
4. **Scaffold shipped gradlew WITHOUT gradle-wrapper.jar** — `./gradlew` fails everywhere.
   Jar is binary, can't be authored as text. FIX: removed wrapper; CI uses `gradle` from
   `gradle/actions/setup-gradle` pinned to **8.10.2** (Gradle 9 breaks the Spring
   dependency-management plugin). All steps call `gradle`, never `./gradlew`.
5. **configure stage never passed API_ADMIN_PASSWORD** to render-node-json.py -> app would fail
   to resolve `@Value("${app.security.admin-password}")` at boot. Added it + DB_PORT.
6. **Chef `podman login` used a bash here-string** (`<<<`) in `execute`, which runs under /bin/sh.
   Rewrote as `printf | podman login --password-stdin`, token via `environment`.
7. **Secret scanner** flagged the Clair datastore credential 3x. Final: generated per-run with
   openssl inside scripts/clair-up.sh, passed via mode-600 `--env-file` deleted right after
   container start (also keeps it out of /proc argv).

## Key decisions
- **Chef, not Ansible** (user request): chef-solo via `chef-client --local-mode` over SSH,
  cinc-client 18.5.0 bootstrapped by scripts/run-chef.sh. No Chef Server.
- **Dedicated VPC** (user request): 10.20.0.0/16, public subnet + 2 private DB subnets.
  NO NAT gateway (saves ~$33/mo); app in public subnet with EIP.
- **REAL CLAIR** (user request, reversed Trivy): registry:2 + postgres:15 + clair:4.7.4 combo,
  in-job on --network host. clairctl -> scripts/clair-gate.py fails on HIGH/CRITICAL.
- **JaCoCo 90%** enforced; only the Spring `main()` class excluded.

## Gotchas
- UDAP D2 profile allows ONE container level — subnets are sibling containers, not nested.
- Pipeline spec steps allow NO `if:` and no stage-level `services:`. Hence Clair runs as podman
  containers and all teardown/diagnostics live in the scripts via `trap EXIT`.
- Clair combo mode loads its CVE DB on first start -> first run slow. Stage timeout 45 min.
- RDS requires a 2-AZ subnet group even for single-AZ instances.
- `aws_vpc_security_group_ingress_rule` standalone so app<->db SGs reference each other safely.

## Open risks to watch on the FIRST CI run
- **clairctl download URL** is a pinned GitHub release asset
  (`releases/download/v4.7.4/clairctl-linux-amd64`). Fix-memory has a CONFIRMED past failure of
  exactly this shape (pinned trivy asset 404 -> `curl -f` exit 22 kills the step). If the asset
  name is wrong, the scan stage fails fast — fix by correcting the asset name/version.
- **JaCoCo 90%** was never actually executed (sandbox died before the test stage). If CI reports
  under 90%, the fix is MORE TESTS, never a lower threshold.
- **checkstyle/pmd/spotbugs** never executed either — first real run is in CI.

## Secrets contract
Platform: PROJECT_NAME, TF_STATE_BUCKET, SSH_USER, SSH_PRIVATE_KEY, SSH_PUBLIC_KEY,
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, GITHUB_TOKEN.
Agent-set AFTER first push: DB_PASSWORD, API_ADMIN_PASSWORD (alphanumeric, >=20 chars).
