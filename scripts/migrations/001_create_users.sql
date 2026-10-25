-- Migration: 001_create_users.sql
-- Description: Create core extensions, users table, quotas, and updated_at triggers

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

-- 3. Create Index on Email
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- 4. Create Automatic updated_at Trigger Function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. Attach Trigger to users table
DROP TRIGGER IF EXISTS set_users_updated_at ON users;
CREATE TRIGGER set_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
