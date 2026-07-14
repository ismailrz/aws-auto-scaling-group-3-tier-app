# AWS Deployment Guide — Auto Scaling Groups (Production-Grade)

This walks through deploying the Todo app as a real 3-tier architecture on AWS:
two independently-scaled EC2 Auto Scaling Groups (frontend, backend) and an
RDS PostgreSQL instance, fronted by an Application Load Balancer.

It's written for the AWS Console (with AWS CLI commands where the console is
too tedious to repeat), not Terraform/CDK — the goal is to *see* every moving
part of an ASG, not hide it behind IaC state.

## Architecture

![Architecture diagram](./docs/architecture.svg)

(Editable source: [`docs/architecture.mmd`](./docs/architecture.mmd), a
Mermaid diagram GitHub also renders inline.)

Two ASGs, not one, because the tiers scale on different signals (frontend
scales on request volume/CPU serving HTML; backend scales on request volume
and DB-bound latency) and you don't want a frontend traffic spike to
over-provision backend capacity or vice versa.

The backend ALB is **public**, not internal — the browser calls
`api.yourdomain.com` directly from client-side JS (see
`frontend/src/lib/api.ts`). If you want the backend fully private, the
frontend would need to proxy API calls server-side instead; that's a
follow-up hardening step, not covered here.

## Domain vs. no domain

Pick one before you start — it changes a handful of concrete values used
throughout (`VITE_API_URL`, `CORS_ORIGINS`, the ALB's listener/routing setup)
but **nothing in the application code**, and you can switch from "no domain"
to "with domain" later without re-architecting.

- **With a domain** — host-based routing on the ALB
  (`app.yourdomain.com` / `api.yourdomain.com`), a real ACM certificate,
  HTTPS end-to-end. This is what the architecture diagram above shows. Steps
  below are tagged **[domain]**.
- **Without a domain** — skip Route 53 and ACM entirely. The ALB gets a DNS
  name automatically the moment you create it (e.g.
  `todo-alb-1234567890.us-east-1.elb.amazonaws.com`); use that directly. With
  only one hostname to work with, use **path-based routing** instead of
  host-based, and the listener is **HTTP only** — ACM can't issue a
  certificate for a domain you don't own, and can't validate the ALB's own
  AWS-owned DNS name. Steps below are tagged **[no domain]**.
  Don't leave this running for real traffic: no TLS means requests (including
  whatever `Todo` data you type in) travel in the clear. It's a legitimate
  way to get the ASG/ALB/RDS mechanics working today and swap in a real
  domain later — see §12.

**Ordering catch if you're going domain-less:** the frontend's
`VITE_API_URL` is baked in at *build time* (§6), but without a domain that
value is the ALB's DNS name, which doesn't exist until the ALB does (§8). So
if you have no domain, do **§8 before §6** — create the target groups and
ALB first (it's fine for them to have zero registered targets briefly), note
the DNS name it's assigned, then come back to §6.

## 0. Prerequisites

- A registered domain (or a subdomain) you can point at AWS, and its zone in
  Route 53 (or delegated to it) — **only if going the [domain] route**; skip
  this if you're doing [no domain] for now.
- The AWS CLI configured (`aws configure`) with an account that has admin
  access for setup.
- This repo pushed somewhere your EC2 instances can `git clone` it (a deploy
  key or a GitHub App/PAT scoped read-only to this repo — do **not** use your
  personal SSH key on a golden AMI).

Region used throughout: `us-east-1`. Swap for your own; keep it consistent
everywhere below.

## 1. Network

Use two AZs minimum — everything below (ASGs, ALB, RDS Multi-AZ) depends on
subnets existing in at least two AZs, which is the actual mechanism that
makes this "production grade" rather than a single point of failure.

Create (VPC console → "VPC and more" wizard, or manually):

| Subnet | AZ-a CIDR | AZ-b CIDR | Purpose |
|---|---|---|---|
| public | 10.0.0.0/24 | 10.0.1.0/24 | ALB, NAT Gateway |
| private-app | 10.0.10.0/24 | 10.0.11.0/24 | EC2 ASGs (frontend + backend) |
| private-db | 10.0.20.0/24 | 10.0.21.0/24 | RDS |

- Internet Gateway attached to the VPC, routed from the public subnets.
- One NAT Gateway per AZ in production (so a NAT failure doesn't take down an
  entire AZ's outbound traffic); one shared NAT Gateway is an acceptable cost
  tradeoff while practicing. Private-app subnets route `0.0.0.0/0` through
  it.
- private-db subnets need **no** route to the internet at all.
- VPC endpoints (Gateway endpoint for S3, Interface endpoints for
  Secrets Manager + SSM + SSM Messages + EC2 Messages) let instances in
  private subnets reach those AWS APIs without going through NAT — cheaper
  and reduces your NAT Gateway's blast radius. Worth adding once the basic
  setup works.

## 2. Security groups

| SG | Inbound | Attached to |
|---|---|---|
| `sg-alb` | 443/80 from `0.0.0.0/0` | ALB |
| `sg-frontend` | 3000 from `sg-alb` only | frontend ASG instances |
| `sg-backend` | 8000 from `sg-alb` only | backend ASG instances |
| `sg-rds` | 5432 from `sg-backend` only | RDS instance |

Nothing allows SSH (port 22) from anywhere — see §6 on Session Manager
instead of SSH keys.

## 3. RDS PostgreSQL

Console → RDS → Create database:

- Engine: PostgreSQL (latest stable).
- Template: Production (enables Multi-AZ by default).
- Instance class: `db.t4g.micro` is enough for practice load; size up for
  real traffic.
- Multi-AZ deployment: **yes** — this is what makes a database failure
  survivable (automatic failover to the standby, typically under a minute)
  instead of an outage.
- Storage: gp3, 20 GB, with storage autoscaling enabled (cap it, e.g. 100 GB,
  so a runaway table can't autoscale your bill into orbit).
- Credentials: let RDS manage the master password in **Secrets Manager**
  (checkbox in the console) rather than typing one in — this also gives you
  automatic rotation later for free.
- VPC: the one from §1, subnet group spanning both private-db subnets.
- Public access: **No**.
- Security group: `sg-rds`.
- Backups: retain 7 days minimum; enable deletion protection.
- Note the resulting endpoint hostname and the Secrets Manager secret ARN —
  both are needed in §5.

The app currently creates its schema with `Base.metadata.create_all()` on
startup (see `backend/app/main.py`) — convenient for local dev, but with
multiple backend instances starting simultaneously during a scale-out event,
concurrent `CREATE TABLE` calls can race. Before going further than practice
with this, switch to Alembic migrations run once (e.g. via SSM `run-command`
against a single instance, or a one-off ECS/CodeBuild task) as part of the
deploy step in §8, and remove `create_all()` from the app's startup path.

## 4. IAM

Create one instance role per tier (both get the same baseline, backend adds
one policy):

**Baseline (both tiers):**
- `AmazonSSMManagedInstanceCore` — enables Session Manager (§6).
- `CloudWatchAgentServerPolicy` — lets the CloudWatch agent ship logs/metrics.

**Backend only:**
- Inline policy granting `secretsmanager:GetSecretValue` scoped to exactly
  the RDS secret's ARN from §3 — not `*`.

Create an instance profile from each role and attach it in the Launch
Template (§7). No IAM users, no long-lived access keys on the instances —
everything is scoped through the instance role.

## 5. Secrets

The RDS-managed secret from §3 holds a JSON blob (`username`, `password`,
`host`, `port`, `dbname`, ...), not a ready-to-use `DATABASE_URL`. Either:

- Store a second, small secret `todo/backend/database-url` containing the
  fully-assembled SQLAlchemy URL
  (`postgresql+psycopg2://user:pass@host:5432/todo`), rebuilt whenever the
  password rotates, **or**
- Have `deploy/backend/user-data.sh` fetch the RDS secret's JSON and
  assemble the URL at boot instead of reading a pre-built one.

The provided `deploy/backend/user-data.sh` assumes the first (simpler)
option — update `SECRET_ID` and `REGION` in that file to match what you
created. It also sets `CORS_ORIGINS`, which needs the same domain-vs-no-domain
value as `VITE_API_URL` in §6:
- **[domain]**: `https://app.yourdomain.com`
- **[no domain]**: `http://<your-alb-dns-name>`

## 6. Golden AMI (per tier, per release)

**[no domain] Do §8 first** and come back here with the ALB's DNS name in
hand — see the ordering note above.

No CodeDeploy, no Docker — matching this repo's systemd-based deployment
model. Each release, you bake a fresh AMI with the code and dependencies
already installed, so instances boot fast and deterministically instead of
`git clone`+`pip install`-ing on every scale-out event (slow, and a
transient GitHub/PyPI outage shouldn't be able to block you from scaling).

For each tier:

1. Launch a temporary "builder" EC2 instance from Amazon Linux 2023, in a
   public subnet (needs internet access to install packages — it's
   throwaway, torn down after imaging).
2. Attach the `AmazonSSMManagedInstanceCore` role from §4 to the builder
   instance, then connect without SSH: console → EC2 → Instances → select
   the builder → Connect → Session Manager tab → Connect (or
   `aws ssm start-session --target <instance-id>` from the CLI). Run
   `deploy/backend/bootstrap-ami.sh` or `deploy/frontend/bootstrap-ami.sh`
   from this repo. Edit `REPO_URL` at the top of each script first, and (for
   the frontend) `VITE_API_URL`:
   - **[domain]**: `https://api.yourdomain.com`
   - **[no domain]**: `http://<your-alb-dns-name>` (no trailing path — the
     app's routes already start with `/`, e.g. `/todos`)
3. Console → EC2 → Instances → select the builder → Actions → Image and
   templates → Create image. Name it e.g. `todo-backend-2026-07-14`.
4. Terminate the builder instance once the image status is `available`.

Repeat this for every release. It's more manual than a CI/CD pipeline, but
it's the mechanism actually worth understanding before automating it away.

## 7. Launch Templates

One per tier. Console → EC2 → Launch Templates → Create:

| Field | Backend | Frontend |
|---|---|---|
| AMI | `todo-backend-<date>` from §6 | `todo-frontend-<date>` from §6 |
| Instance type | `t3.small` | `t3.small` |
| Key pair | none | none |
| Subnets | (set at ASG level, not here) | (set at ASG level, not here) |
| Security group | `sg-backend` | `sg-frontend` |
| IAM instance profile | backend role from §4 | frontend role from §4 |
| User data | `deploy/backend/user-data.sh` (base64, console does this for you) | `deploy/frontend/user-data.sh` |
| EBS volume | 8 GB gp3, encrypted | 8 GB gp3, encrypted |
| Metadata options | IMDSv2 **required** | IMDSv2 **required** |

IMDSv2-required closes off the classic SSRF-to-instance-metadata attack path
— there's no reason to leave IMDSv1 open on a new deployment.

## 8. Target Groups + ALB + routing

Two target groups either way, both **instance** type, both **HTTP**:
- `tg-backend`, port 8000, health check path `/health` (already implemented
  in `backend/app/main.py`).
- `tg-frontend`, port 3000, health check path `/` (Nitro's node-server
  returns 200 for the app shell).
- Health check thresholds: 2 consecutive successes to mark healthy, 2
  consecutive failures to mark unhealthy, 15s interval — fast enough that a
  bad instance is pulled from rotation within ~30s.

It's fine to create these — and the ALB below — before any instances exist;
they'll just show zero registered targets until §9 stands up the ASGs.

### 8a. [domain]

1. Request an ACM certificate for `app.yourdomain.com` and
   `api.yourdomain.com` (or a wildcard `*.yourdomain.com`) — DNS validation,
   in the **same region** as the ALB.
2. Create the ALB in the public subnets, security group `sg-alb`.
   - Listener 443: default action can 404; add two host-header rules —
     `Host is app.yourdomain.com` → `tg-frontend`, `Host is
     api.yourdomain.com` → `tg-backend`.
   - Listener 80: single rule, redirect to 443.
3. Route 53: `A`/`ALIAS` records for `app.yourdomain.com` and
   `api.yourdomain.com` pointing at the ALB.

### 8b. [no domain]

1. Create the ALB in the public subnets, security group `sg-alb`, with a
   single **HTTP:80** listener — no ACM cert to attach, since there's no
   domain to validate one against.
2. Add listener rules, evaluated top-down:
   - Rule 1: path pattern `/todos*` **or** `/health` → `tg-backend`.
   - Default action (no match) → `tg-frontend`.
   This works with zero backend code changes because the API's routes
   already live at the root (`/todos`, `/health`) rather than under an
   `/api` prefix — the ALB has no path-rewrite capability, so whatever
   prefix you route on has to be the app's actual path.
3. Note the ALB's DNS name (EC2 → Load Balancers → your ALB → "DNS name"
   column) — that's the value §5 and §6 needed.
4. No Route 53 step — you hit the ALB's DNS name directly.

Optional upgrade if you want HTTPS without owning a domain: put a CloudFront
distribution in front of this ALB. CloudFront's own `*.cloudfront.net` domain
comes with a valid AWS-issued certificate automatically — no domain
ownership required. Not detailed here; it adds cache-behavior configuration
you'd need to disable/passthrough correctly for the API to keep working.

## 9. Auto Scaling Groups

One per tier, using the matching Launch Template from §7:

| Setting | Backend | Frontend |
|---|---|---|
| Subnets | private-app, both AZs | private-app, both AZs |
| Target group | `tg-backend` | `tg-frontend` |
| Min / Desired / Max | 2 / 2 / 6 | 2 / 2 / 4 |
| Health check type | **ELB** (not just EC2) | **ELB** |
| Health check grace period | 60s | 30s |

Health check type must be ELB, not the default EC2-status-only check —
EC2 status checks can't tell that your app process crashed while the OS is
still fine; only the ALB target group health check (hitting `/health` or
`/`) can.

Min = 2 in both tiers, across 2 AZs, is the actual HA guarantee here: losing
one AZ still leaves one healthy instance per tier serving traffic.

### Scaling policies

Backend — target tracking on **ALB request count per target** (a better
signal than CPU for an I/O-bound API waiting on Postgres, since a instance
can be maxed out on DB-wait latency while CPU sits idle): target ~200
requests/target, scale-out cooldown default, min capacity 2.

Frontend — target tracking on **average CPU utilization**, target 50%
(SSR/static rendering is more CPU-bound than I/O-bound).

Both: also add a target-tracking policy on CPU as a second line of defense
even on the backend — belt-and-suspenders costs nothing and protects against
a bug in one metric's assumptions.

### Instance refresh (how deploys actually roll out)

This is how a new AMI from §6 actually reaches production once you've
created a new Launch Template version pointing at it:

1. EC2 → Launch Templates → your template → Actions → "Set default version"
   to the new version (or leave default alone and specify the version
   explicitly in the refresh — either works).
2. EC2 → Auto Scaling Groups → your ASG → Instance refresh → Start:
   - Minimum healthy percentage: 100% (never drop below current capacity
     during the rollout — costs one extra instance briefly, buys zero
     downtime).
   - Warm-up time: match the health check grace period above.
3. ASG launches new instances from the new AMI, waits for them to pass
   health checks, then terminates old instances one batch at a time —
   automatically, with automatic rollback if new instances fail health
   checks.

CLI equivalent, useful once you're comfortable with the console flow:

```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name todo-backend \
  --preferences '{"MinHealthyPercentage": 100, "InstanceWarmup": 60}'
```

## 10. Observability

- CloudWatch agent (IAM policy already attached in §4) shipping the
  `journalctl` output of `todo-backend`/`todo-frontend` to CloudWatch Logs —
  install and configure it as part of the golden AMI in §6 so you don't lose
  logs the moment an instance is terminated.
- ALB access logs → S3 (enable on the ALB; free, just S3 storage cost).
- CloudWatch alarms on: ASG `GroupInServiceInstances` dropping below min,
  target group `UnHealthyHostCount` > 0, RDS `FreeStorageSpace` and
  `CPUUtilization`. Wire them to an SNS topic you're actually subscribed to
  — an alarm nobody sees is a false sense of safety.
- RDS Performance Insights (free tier available) if you want to see what
  queries are actually driving load once you start load testing (§11).

## 11. Prove the scaling actually works

The entire point of this exercise — generate load and watch the ASG react:

```bash
# hey: https://github.com/rakyll/hey

# [domain]
hey -z 3m -c 50 https://api.yourdomain.com/todos

# [no domain]
hey -z 3m -c 50 http://<your-alb-dns-name>/todos
```

Watch, in parallel:
- EC2 → Auto Scaling Groups → your ASG → Activity tab — new "Launching"
  activities should appear once the target-tracking alarm breaches.
- CloudWatch → the target-tracking alarm itself, transitioning to `ALARM`.
- The target group's registered targets count climbing.

Expect a few minutes of lag between load starting and new instances
becoming healthy (metric aggregation window + instance boot + health check
grace period) — that lag is itself the reason `min` capacity should reflect
your steady-state floor, not rely on scale-out to cover normal traffic.

## 12. Production hardening checklist (beyond what's above)

- [ ] If running [no domain]/HTTP today: point a real domain at the ALB, add
      the ACM cert + host-based routing from §8a, then rebuild both golden
      AMIs (`VITE_API_URL`/`CORS_ORIGINS` are baked in, not runtime-configurable)
      and roll them out via instance refresh (§9).
- [ ] AWS WAF on the ALB (rate-based rule at minimum, since `api.` is
      public).
- [ ] Switch schema management from `create_all()` to Alembic migrations
      (§3).
- [ ] Secrets Manager automatic rotation for the RDS password.
- [ ] Second NAT Gateway (one per AZ) once cost allows.
- [ ] GuardDuty + Security Hub enabled on the account.
- [ ] Scheduled scaling on top of target tracking if traffic has a known
      daily/weekly pattern (pre-warm before it hits rather than reacting
      after).
- [ ] Backup/restore drill for RDS — a Multi-AZ deployment protects against
      an AZ failure, not against a bad migration or a dropped table.
