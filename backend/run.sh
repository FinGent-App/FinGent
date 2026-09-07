#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# 1. Pastikan file .env tersedia
if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
fi

# 2. Otomatis nyalakan Docker PostgreSQL jika menggunakan local database & Docker aktif
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if grep -q "5433" .env 2>/dev/null; then
        echo "🐳 Ensuring local PostgreSQL container is running on port 5433..."
        docker compose up -d
    fi
fi

# 3. Virtual environment setup
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate

# 4. Dependency check
echo "📦 Checking dependencies..."
pip install -r requirements.txt --quiet

# 5. Pastikan port 8000 bersih dari proses lama
OLD_PID=$(lsof -ti :8000 2>/dev/null || true)
if [ -n "$OLD_PID" ]; then
    echo "🧹 Port 8000 sedang terpakai, membersihkan proses lama (PID: $OLD_PID)..."
    kill -9 $OLD_PID 2>/dev/null || true
    sleep 1
fi

# 6. Jalankan server FastAPI
echo "🚀 Starting FinGent Backend on http://0.0.0.0:8000..."
exec uvicorn main:app --host 0.0.0.0 --port 8000 --reload
