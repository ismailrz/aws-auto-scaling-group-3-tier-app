# Todo App — TanStack Start + FastAPI + PostgreSQL

A minimal Todo CRUD app used to practice deploying a 3-tier architecture behind an AWS Auto Scaling Group (frontend ASG + backend ASG + RDS Postgres).

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

## Deploying to EC2 (practice target)

Both tiers are plain processes (no Docker) so they can run under `systemd` on EC2 instances inside their own Auto Scaling Groups:

- **Backend ASG**: run `uvicorn app.main:app --host 0.0.0.0 --port 8000` behind an ALB, pointed at an RDS Postgres instance via `DATABASE_URL`.
- **Frontend ASG**: run `npm run build && node .output/server/index.mjs` (Nitro's `node-server` preset) behind its own ALB, with `VITE_API_URL` pointed at the backend ALB's DNS name (baked in at build time).
- Both apps expose `/health`-style responses (backend: `/health`, frontend: `/` returns 200) suitable for ALB target group health checks.
# aws-auto-scaling-group-3-tier-app
