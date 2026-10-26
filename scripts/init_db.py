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

migrations_dir = Path(__file__).resolve().parent / "migrations"
migration_files = sorted(migrations_dir.glob("*.sql"))

if not migration_files:
    print(f"❌ Error: No migration files found in {migrations_dir}.")
    sys.exit(1)

print("🔗 Connecting to Neon PostgreSQL...")
try:
    with psycopg.connect(conn_str) as conn:
        with conn.cursor() as cur:
            # 1. Apply Migrations in order
            for migration_file in migration_files:
                print(f"📄 Applying {migration_file.name}...")
                sql = migration_file.read_text()
                cur.execute(sql)
                conn.commit()
                print(f"✅ {migration_file.name} applied successfully!")

            # 2. Inspect All Created Tables
            cur.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
                ORDER BY table_name;
            """)
            tables = [row[0] for row in cur.fetchall()]
            print("\n📊 Public Tables in Neon Database:")
            for t in tables:
                cur.execute(f"SELECT COUNT(*) FROM {t};")
                cnt = cur.fetchone()[0]
                print(f"  • {t:<25} (Rows: {cnt})")

            # 3. Inspect Custom Types (Enums)
            cur.execute("""
                SELECT t.typname
                FROM pg_type t 
                JOIN pg_namespace n ON 1=1 AND t.typnamespace = n.oid 
                WHERE n.nspname = 'public' AND t.typtype = 'e'
                ORDER BY t.typname;
            """)
            enums = [row[0] for row in cur.fetchall()]
            print("\n🏷️ Custom Enums in Neon Database:")
            for e in enums:
                print(f"  • {e}")

except Exception as e:
    print("❌ Database operation failed:", e)
    sys.exit(1)

print("\n🎉 Neon database setup complete!")
