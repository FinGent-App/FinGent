import os
import ssl
import logging
from typing import Any, List, Optional, Dict
import asyncpg
from dotenv import load_dotenv

# Load environment variables from .env
load_dotenv()

logger = logging.getLogger("FinGent.Database")

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://fingent_admin:fingent_password123@localhost:5432/fingent_db"
)
DB_POOL_MIN_SIZE = int(os.getenv("DB_POOL_MIN_SIZE", "2"))
DB_POOL_MAX_SIZE = int(os.getenv("DB_POOL_MAX_SIZE", "10"))
DB_TIMEOUT_SECONDS = float(os.getenv("DB_TIMEOUT_SECONDS", "15"))

# Global connection pool instance
_pool: Optional[asyncpg.Pool] = None


def _get_ssl_context(dsn: str) -> Optional[Any]:
    """
    Returns appropriate SSL context based on DSN.
    Supabase, Neon, and AWS RDS require SSL.
    """
    lower_dsn = dsn.lower()
    if "supabase" in lower_dsn or "neon.tech" in lower_dsn or "sslmode=require" in lower_dsn:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx
    return None


async def init_db_pool() -> Optional[asyncpg.Pool]:
    """
    Initializes the PostgreSQL async connection pool.
    Auto-applies migrations if connected successfully.
    """
    global _pool
    if _pool is not None:
        return _pool

    # Clean DSN of sslmode query parameter if present since asyncpg handles it via ssl arg
    dsn = DATABASE_URL
    clean_dsn = dsn
    if "?sslmode=" in dsn:
        clean_dsn = dsn.split("?sslmode=")[0]
    elif "&sslmode=" in dsn:
        clean_dsn = dsn.replace("&sslmode=require", "").replace("&sslmode=prefer", "")

    ssl_context = _get_ssl_context(dsn)

    try:
        logger.info("Connecting to PostgreSQL pool at %s...", clean_dsn.split("@")[-1] if "@" in clean_dsn else clean_dsn)
        _pool = await asyncpg.create_pool(
            dsn=clean_dsn,
            min_size=DB_POOL_MIN_SIZE,
            max_size=DB_POOL_MAX_SIZE,
            timeout=DB_TIMEOUT_SECONDS,
            ssl=ssl_context,
            statement_cache_size=0 if ssl_context is not None else 100
        )
        logger.info("✅ PostgreSQL connection pool initialized successfully.")
        
        # Auto-apply schema migrations
        await apply_migrations()
        return _pool
    except Exception as e:
        logger.warning("⚠️ PostgreSQL connection failed: %s. Continuing with database features offline.", str(e))
        _pool = None
        return None


async def close_db_pool():
    """Closes all active database connections in pool."""
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None
        logger.info("PostgreSQL connection pool closed.")


def get_pool() -> Optional[asyncpg.Pool]:
    """Returns active database pool or None if offline."""
    return _pool


def is_connected() -> bool:
    """Checks if database pool is active."""
    return _pool is not None


async def apply_migrations():
    """
    Applies schema migrations from migrations/*.sql in alphabetical order.
    Ensures tables and indices exist in local or Supabase database.
    """
    if _pool is None:
        return

    migrations_dir = os.path.join(os.path.dirname(__file__), "migrations")
    if not os.path.exists(migrations_dir):
        logger.warning("Migrations directory not found at %s", migrations_dir)
        return

    try:
        sql_files = sorted([f for f in os.listdir(migrations_dir) if f.endswith(".sql")])
        async with _pool.acquire() as conn:
            for sql_file in sql_files:
                file_path = os.path.join(migrations_dir, sql_file)
                with open(file_path, "r", encoding="utf-8") as f:
                    sql = f.read()
                await conn.execute(sql)
                logger.info("✅ Migration applied: %s", sql_file)
    except Exception as e:
        logger.error("❌ Failed to apply database migrations: %s", str(e))


# ==============================================================================
# Pure Raw SQL Query Helpers (Fast, Parameterized, SQL-Injection Safe)
# ==============================================================================

async def fetch_all(query: str, *args) -> List[Dict[str, Any]]:
    """Executes SELECT query and returns list of dictionaries."""
    if _pool is None:
        raise RuntimeError("PostgreSQL database is currently disconnected.")
    async with _pool.acquire() as conn:
        records = await conn.fetch(query, *args)
        return [dict(record) for record in records]


async def fetch_one(query: str, *args) -> Optional[Dict[str, Any]]:
    """Executes SELECT query and returns single dictionary or None."""
    if _pool is None:
        raise RuntimeError("PostgreSQL database is currently disconnected.")
    async with _pool.acquire() as conn:
        record = await conn.fetchrow(query, *args)
        return dict(record) if record else None


async def fetch_val(query: str, *args) -> Any:
    """Executes query and returns scalar value (e.g. COUNT(*))."""
    if _pool is None:
        raise RuntimeError("PostgreSQL database is currently disconnected.")
    async with _pool.acquire() as conn:
        return await conn.fetchval(query, *args)


async def execute(query: str, *args) -> str:
    """Executes INSERT, UPDATE, or DELETE query."""
    if _pool is None:
        raise RuntimeError("PostgreSQL database is currently disconnected.")
    async with _pool.acquire() as conn:
        return await conn.execute(query, *args)


async def execute_many(query: str, args_list: List[tuple]) -> None:
    """Executes batch operations efficiently."""
    if _pool is None:
        raise RuntimeError("PostgreSQL database is currently disconnected.")
    async with _pool.acquire() as conn:
        await conn.executemany(query, args_list)
