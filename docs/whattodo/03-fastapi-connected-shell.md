# Task 03 — FastAPI Backend & Connected Shell

**Date:** October 2026\
**Status:** Ready to execute\
**Context:** [09-complete-developer-handbook.md](../knowledge/09-complete-developer-handbook.md) (Phase 1: The Connected Shell)\
**Database:** Neon Serverless PostgreSQL (`ep-broad-scene-b5d1f68v-pooler`)

---

## 🧠 The Big Picture — What Is This Task?

Right now your v2note project has:

- ✅ A **Next.js frontend** (the default starter page at `localhost:3000`)
- ✅ A **Neon PostgreSQL database** with 9 tables (seeded via `scripts/init_db.py`)
- ❌ **No backend server** — there is nothing sitting between your frontend and your database

**Task 03 builds the middle layer** — a FastAPI (Python) server inside `services/api/` that:

1. Connects to your Neon database using async SQLAlchemy
2. Exposes health-check endpoints to prove everything is wired
3. Gets called by the Next.js frontend to display a live "connected" status

```
┌──────────────┐      HTTP JSON       ┌──────────────┐       SQL        ┌──────────────┐
│  Next.js     │  ──────────────────► │  FastAPI      │ ──────────────► │  Neon        │
│  :3000       │  ◄────────────────── │  :8000        │ ◄────────────── │  PostgreSQL  │
│  (browser)   │      response        │  (Python)     │     result      │  (cloud DB)  │
└──────────────┘                      └──────────────┘                  └──────────────┘
```

---

## ❓ Why Is This Needed?

### 1. You can't query Postgres from the browser

Your terminal attempt — `await db.execute(text("SELECT count(*) FROM users"))` — failed because that's Python async code. It can only run inside a Python async runtime (like FastAPI), not in a shell or browser.

### 2. Security: secrets stay server-side

Your `NEON_DB_CONNECTION_STRING` contains your database password. A backend server holds these secrets and exposes only safe JSON endpoints to the frontend.

### 3. It's your app's "traffic cop"

Every future feature (user auth, lecture uploads, AI processing) will go through this FastAPI layer. This task is the foundation for everything that follows.

---

## 📋 Step-by-Step — How to Do It

---

### Step 1: Create the `services/api/` project structure

**Why:** FastAPI needs its own isolated Python environment inside `services/api/` so it doesn't conflict with the root `pyproject.toml` (which uses `psycopg` for migrations).

**Files to create:**

```
services/api/
├── pyproject.toml          ← Python deps for FastAPI
├── .env                    ← DB connection string (symlink or copy)
└── app/
    ├── __init__.py         ← Makes 'app' a Python package
    ├── main.py             ← FastAPI app entry point + routes
    ├── config.py           ← Pydantic Settings (reads .env)
    └── db/
        ├── __init__.py
        └── session.py      ← Async SQLAlchemy engine + session
```

---

### Step 2: Install Python dependencies

**Why:** You need these specific packages:

| Package             | Why                                                              |
| ------------------- | ---------------------------------------------------------------- |
| `fastapi`           | The web framework — defines routes, handles HTTP                 |
| `uvicorn[standard]` | ASGI server — actually runs FastAPI and serves requests          |
| `sqlalchemy`        | ORM/query builder — talks to Postgres with Python objects        |
| `asyncpg`           | Async Postgres driver — lets SQLAlchemy use `await` for DB calls |
| `pydantic-settings` | Reads your `.env` file into typed Python config objects          |

**How — run from `services/api/`:**

```bash
cd services/api
uv init .
uv add fastapi "uvicorn[standard]" sqlalchemy asyncpg pydantic-settings
```

---

### Step 3: Create `app/config.py` — Environment Config

**Why:** Instead of calling `os.getenv()` everywhere, Pydantic Settings gives you a single typed config object that auto-reads your `.env` file and validates it at startup. If the DB string is missing, the app crashes immediately with a clear error instead of silently breaking later.

**What it does:**

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    NEON_DB_CONNECTION_STRING: str    # ← must be set, or app won't start

    model_config = {"env_file": ".env"}

settings = Settings()
```

**How it works under the hood:**

1. On import, `Settings()` is called
2. Pydantic looks for `NEON_DB_CONNECTION_STRING` in environment variables first, then in `.env`
3. If it's missing → `ValidationError` with a clear message
4. If found → `settings.NEON_DB_CONNECTION_STRING` is a typed `str` you can use anywhere

---

### Step 4: Create `app/db/session.py` — Async Database Engine

**Why:** This is the single place where your app creates a connection pool to Neon. Every endpoint that needs the database will borrow a connection from this pool.

**What it does:**

- Converts your `postgresql://...` URL to `postgresql+asyncpg://...` (the async driver format)
- Enables `pool_pre_ping=True` so stale connections to Neon are auto-detected
- Provides a `get_db()` async generator that FastAPI uses as a dependency

**Key concept — "Dependency Injection":**

```python
# Instead of this (bad — creates new connection every time):
@app.get("/something")
async def something():
    engine = create_engine(...)  # DON'T

# You do this (good — borrows from pool):
@app.get("/something")
async def something(db: AsyncSession = Depends(get_db)):
    result = await db.execute(text("SELECT 1"))  # reuses pooled connection
```

**What `pool_pre_ping=True` does:** Neon is serverless — it may close idle connections. `pool_pre_ping` sends a tiny `SELECT 1` before each real query to check if the connection is still alive. If it's dead, SQLAlchemy silently replaces it with a fresh one. Without this, you'd get random `connection reset` errors.

**What the URL conversion does:** Your `.env` has: `postgresql://neondb_owner:...@...neon.tech/neondb?sslmode=require` SQLAlchemy async needs: `postgresql+asyncpg://neondb_owner:...@...neon.tech/neondb?ssl=true`

The code replaces `postgresql://` → `postgresql+asyncpg://` and `sslmode=require` → `ssl=true` (asyncpg uses a different SSL parameter name).

---

### Step 5: Create `app/main.py` — The FastAPI Application

**Why:** This is the heart of your backend. It defines:

- The FastAPI app instance
- CORS middleware (so `localhost:3000` can call `localhost:8000`)
- Two health check routes

**The two endpoints:**

#### `GET /api/health` — Basic Ping

```json
{"status": "ok", "service": "v2note API"}
```

Just proves the FastAPI server is running. No DB involved.

#### `GET /api/health/db` — Database Connectivity Proof

```json
{"status": "ok", "database": "connected", "tables": 9}
```

Runs a query against `information_schema.tables` to count how many tables exist in the `public` schema. This proves:

1. The async connection to Neon works
2. Your 9 tables (created by `init_db.py`) exist

**CORS — why you need it:**

When your browser (at `localhost:3000`) tries to fetch from `localhost:8000`, the browser blocks it by default — this is the "Same-Origin Policy". CORS middleware tells the browser "yes, requests from `localhost:3000` are allowed."

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_methods=["*"],
    allow_headers=["*"],
)
```

Without this, your frontend `fetch("/api/health")` will fail with:

```
Access to fetch at 'http://localhost:8000/api/health' from origin 'http://localhost:3000'
has been blocked by CORS policy
```

---

### Step 6: Start the FastAPI Server

**Why:** This actually runs your backend so you can test it.

```bash
# From services/api/
uv run uvicorn app.main:app --reload --port 8000
```

| Flag           | Meaning                                                           |
| -------------- | ----------------------------------------------------------------- |
| `app.main:app` | "In the `app/` package, in `main.py`, use the object named `app`" |
| `--reload`     | Auto-restart when you edit Python files (dev only)                |
| `--port 8000`  | Listen on port 8000                                               |

**Verify with curl (in a second terminal):**

```bash
curl http://localhost:8000/api/health
# → {"status":"ok","service":"v2note API"}

curl http://localhost:8000/api/health/db
# → {"status":"ok","database":"connected","tables":9}
```

If you see those JSON responses, the backend is working.

---

### Step 7: Update `next.config.ts` — API Proxy

**Why:** Instead of hardcoding `http://localhost:8000` in your frontend code, you configure Next.js to proxy `/api/*` requests to FastAPI. This means:

- In dev: Next.js forwards to `localhost:8000`
- In production: You change one config line, not 50 fetch calls
- No CORS issues because from the browser's perspective, it's calling the same origin

**How:** Add a `rewrites` rule in `next.config.ts`:

```typescript
const nextConfig: NextConfig = {
  // ... existing config ...
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:8000/api/:path*",
      },
    ];
  },
};
```

**What `rewrites` does:** When the browser requests `http://localhost:3000/api/health`, Next.js intercepts it and internally forwards it to `http://localhost:8000/api/health`. The browser never sees port 8000 — it thinks everything comes from port 3000.

---

### Step 8: Replace `app/page.tsx` — Live Status Dashboard

**Why:** The final proof. Replace the default Next.js starter page with a component that:

1. Calls `/api/health` and `/api/health/db` on page load
2. Shows green "Online" / red "Offline" indicators for both backend and database
3. Displays the table count from the database response

This proves the **full chain** works: Browser → Next.js → FastAPI → Neon → back.

**What the component does:**

```
On mount:
  1. fetch("/api/health")     → if 200 → show green "Backend: Online"
  2. fetch("/api/health/db")  → if 200 → show green "Database: Connected (9 tables)"
  3. If either fails          → show red "Offline" with error message
```

---

## 🔍 Verification Checklist

- [ ] `services/api` runs cleanly via `uv run uvicorn app.main:app --reload --port 8000`.
- [ ] `curl http://localhost:8000/api/health` returns `{"status": "ok", "service": "v2note API"}`.
- [ ] `curl http://localhost:8000/api/health/db` returns `{"status": "ok", "database": "connected", "tables": 9}`.
- [ ] Next.js on `http://localhost:3000` displays an online indicator showing backend and database health.

---

## ⚠️ Common Pitfalls

| Problem                           | Cause                                         | Fix                                                                    |
| --------------------------------- | --------------------------------------------- | ---------------------------------------------------------------------- |
| `ModuleNotFoundError: asyncpg`    | Deps installed in wrong venv                  | Run `uv add` from inside `services/api/`, not project root             |
| CORS error in browser console     | Missing CORS middleware                       | Add `CORSMiddleware` with `allow_origins=["http://localhost:3000"]`    |
| `connection refused` on port 8000 | FastAPI not running                           | Start it with `uv run uvicorn ...` in a separate terminal first        |
| SSL error connecting to Neon      | Missing `sslmode=require`                     | Your `.env` URL already has it — make sure `services/api/.env` matches |
| `asyncpg` can't parse URL         | URL still has `postgresql://` prefix          | Code must convert to `postgresql+asyncpg://`                           |
| `channel_binding=require` error   | asyncpg doesn't support channel binding param | Strip `channel_binding=require` from URL when converting for asyncpg   |
| `await` in terminal fails         | Python async code can't run in shell          | That's exactly what FastAPI is for — it provides the async runtime     |

---

## 🔑 Key Concept Summary

> **What you tried in the terminal** (`await db.execute(...)`) is exactly what FastAPI will do for you — but inside a proper async Python server. You write the same SQLAlchemy query, FastAPI runs it asynchronously, and returns the result as JSON to whoever asked (curl, browser, frontend).

The entire point of this task is: **give your database a "front door" that the browser can knock on.**
