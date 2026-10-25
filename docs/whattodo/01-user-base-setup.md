# Task 01: Set Up the User Base Table in Neon PostgreSQL

**Date:** October 2026  
**Status:** Ready to execute  
**Context:** [05-database-schema-and-neon-pg.md](../knowledge/05-database-schema-and-neon-pg.md) & [09-complete-developer-handbook.md](../knowledge/09-complete-developer-handbook.md)  
**Database:** Neon Serverless PostgreSQL (`ep-broad-scene-b5d1f68v-pooler`)

---

## 🎯 Goal
Set up the core `users` table and required PostgreSQL extensions in your Neon database, and verify it with a test query.

---

## 📌 The Two Action Items

### 1. Execute the DDL Migration
Create the PostgreSQL extensions and the `users` table with production constraints (tiers, monthly recording quotas, and timestamp triggers).

#### SQL Definition:
```sql
-- 1. Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- 2. Create the Users Table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    full_name VARCHAR(255),
    avatar_url TEXT,
    tier VARCHAR(50) NOT NULL DEFAULT 'free' 
        CHECK (tier IN ('free', 'pro_student', 'campus')),
    monthly_quota_minutes INT NOT NULL DEFAULT 180 
        CHECK (monthly_quota_minutes >= 0),
    minutes_used_this_month INT NOT NULL DEFAULT 0 
        CHECK (minutes_used_this_month >= 0),
    quota_reset_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '1 month'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Create Index on Email for fast lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- 4. Create Automatic updated_at Trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_users_updated_at ON users;
CREATE TRIGGER set_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
```

---

### 2. Run and Verify the Database Setup
You can run this migration using the project's helper script:

```bash
uv run --with "psycopg[binary]" python scripts/init_db.py
```

Or verify directly in the Neon Console SQL Editor or via Python.

---

## 🔍 Verification Checklist
- [ ] Neon database connects successfully over SSL.
- [ ] Extensions (`uuid-ossp`, `pgcrypto`, `vector`, `pg_trgm`) are active.
- [ ] Table `users` exists with 10 columns and primary key `id` (UUID).
- [ ] Test insert creates a dummy user with default tier `'free'` and 180 quota minutes.
- [ ] Querying `SELECT * FROM users` returns the test record.
