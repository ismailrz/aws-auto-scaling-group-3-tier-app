# Todo App — TanStack Start + FastAPI + PostgreSQL

A minimal Todo CRUD app used to practice deploying a 3-tier architecture behind an AWS Auto Scaling Group (frontend ASG + backend ASG + RDS Postgres).

Two ways to deploy the AWS Auto Scaling Group architecture: [DEPLOYMENT.md](./DEPLOYMENT.md) (manual, via the AWS Console/CLI) or [terraform/](./terraform) (the same architecture as code).

## Structure

```
frontend/   TanStack Start (React) app — served by Node (Nitro node-server preset)
backend/    FastAPI app — Todo CRUD API backed by PostgreSQL
docker-compose.yml   Local PostgreSQL only, for development
```

## Run locally

### 1. Database

```bash
docker compose up -d
```

Starts Postgres on `localhost:5432` (user/pass/db: `todo`/`todo`/`todo`).

### 2. Backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --port 8000
```

API docs at http://localhost:8000/docs. Health check at `/health`.

### 3. Frontend

```bash
cd frontend
npm install
cp .env.example .env
npm run dev
```

App at http://localhost:3000.

## Deploying to AWS (Auto Scaling Groups)

Same 3-tier architecture either way — VPC/subnets, RDS Multi-AZ, golden AMIs, Launch Templates, ALB routing, and Auto Scaling Groups with target-tracking + instance-refresh for both tiers. Pick one:

- **[DEPLOYMENT.md](./DEPLOYMENT.md)** — manual, via the AWS Console/CLI. Click/type through every resource yourself; the goal is to *see* every moving part of an ASG rather than hide it behind IaC state. The systemd unit files and bootstrap/user-data scripts it references live under [`deploy/`](./deploy).
- **[terraform/](./terraform)** — the same architecture provisioned declaratively. See [`terraform/README.md`](./terraform/README.md).
