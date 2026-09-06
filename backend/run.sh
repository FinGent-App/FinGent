#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

echo "Activating virtual environment..."
source venv/bin/activate

echo "Checking / installing dependencies..."
pip install -r requirements.txt

echo "Starting FinGent FastAPI Server on http://0.0.0.0:8000..."
exec uvicorn main:app --host 0.0.0.0 --port 8000 --reload
