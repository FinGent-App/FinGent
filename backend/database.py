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
            ssl=ssl_context
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
    Applies initial schema from migrations/001_initial_schema.sql if connected.
    Ensures tables and indices exist in local or Supabase database.
    """
    if _pool is None:
        return

    migration_file = os.path.join(os.path.dirname(__file__), "migrations", "001_initial_schema.sql")
    if not os.path.exists(migration_file):
        logger.warning("Migration file not found at %s", migration_file)
        return

    try:
        with open(migration_file, "r", encoding="utf-8") as f:
            sql = f.read()

        async with _pool.acquire() as conn:
            await conn.execute(sql)
            logger.info("✅ Database schema verified & migrations applied successfully.")
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
