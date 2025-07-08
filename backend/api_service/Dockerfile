# ---- Build image ----
FROM python:3.11-slim

WORKDIR /app

# Install Python deps first (better layer-caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the source code
COPY . .

# Expose Cloud Run port
ENV PORT=8080
EXPOSE 8080

# Start with gunicorn – 1 worker is fine for a small API
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "main:app"]
