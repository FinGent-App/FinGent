FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source code
COPY . .

# Expose port (Google Cloud Run passes PORT environment variable)
ENV PORT=8080
EXPOSE 8080

# Run uvicorn on $PORT
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT}
