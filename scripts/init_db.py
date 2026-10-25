import os
import sys
from pathlib import Path
import psycopg

# Load .env file if present
env_file = Path(__file__).resolve().parent.parent / ".env"
if env_file.exists():
    with open(env_file, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())

conn_str = os.getenv("NEON_DB_CONNECTION_STRING")
if not conn_str:
    print("❌ Error: NEON_DB_CONNECTION_STRING not found in environment or .env file.")
    sys.exit(1)

migration_file = Path(__file__).resolve().parent / "migrations" / "001_create_users.sql"
if not migration_file.exists():
    print(f"❌ Error: Migration file {migration_file} not found.")
    sys.exit(1)

print("🔗 Connecting to Neon PostgreSQL...")
try:
    with psycopg.connect(conn_str) as conn:
        with conn.cursor() as cur:
            # 1. Apply Migration
            print(f"📄 Applying {migration_file.name}...")
            sql = migration_file.read_text()
            cur.execute(sql)
            conn.commit()
            print("✅ Migration applied successfully!")

            # 2. Inspect Created Table
            cur.execute("""
                SELECT column_name, data_type, is_nullable, column_default
                FROM information_schema.columns 
                WHERE table_name = 'users'
                ORDER BY ordinal_position;
            """)
            columns = cur.fetchall()
            print("\n📊 'users' Table Schema in Neon:")
            for col in columns:
                print(f"  • {col[0]:<25} {col[1]:<15} (Nullable: {col[2]}, Default: {col[3]})")

            # 3. Check row count
            cur.execute("SELECT COUNT(*) FROM users;")
            count = cur.fetchone()[0]
            print(f"\n👥 Total users in database: {count}")

            if "--test-seed" in sys.argv:
                print("\n🧪 Running test seed...")
                test_email = "test.student@v2note.local"
                cur.execute("""
                    INSERT INTO users (email, full_name, tier)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (email) DO UPDATE 
                    SET full_name = EXCLUDED.full_name
                    RETURNING id, email, full_name, tier, monthly_quota_minutes, created_at;
                """, (test_email, "Test Student", "free"))
                user = cur.fetchone()
                conn.commit()
                print(f"✅ Test user ready: ID={user[0]}, Email={user[1]}, Tier={user[3]}, Quota={user[4]}m")

except Exception as e:
    print("❌ Database operation failed:", e)
    sys.exit(1)

print("\n🎉 Neon database setup complete!")
