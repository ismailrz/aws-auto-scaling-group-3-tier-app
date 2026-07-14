# Todo App — TanStack Start + FastAPI + PostgreSQL

A minimal Todo CRUD app used to practice deploying a 3-tier architecture behind an AWS Auto Scaling Group (frontend ASG + backend ASG + RDS Postgres).

See [DEPLOYMENT.md](./DEPLOYMENT.md) for the AWS Auto Scaling Group deployment guide.

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

See [DEPLOYMENT.md](./DEPLOYMENT.md) for the full production-grade walkthrough — VPC/subnets, RDS Multi-AZ, golden AMIs, Launch Templates, ALB host-based routing, and the Auto Scaling Group + target-tracking + instance-refresh setup for both tiers. The systemd unit files and bootstrap/user-data scripts it references live under [`deploy/`](./deploy).
