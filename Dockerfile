# syntax=docker/dockerfile:1.6
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Create non-root user
RUN useradd -u 1001 -r -g root -s /sbin/nologin -c "Nonroot User" appuser && \
    mkdir -p /tls && chown -R appuser:root /app /tls

# Install dependencies
COPY requirements.txt /app/
RUN pip install --upgrade pip && pip install -r requirements.txt

# Copy application code
COPY app/ /app/

USER 1001
EXPOSE 8443

CMD ["python", "/app/webhook.py"]


