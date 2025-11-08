# Multi-stage Dockerfile for Locust Load Testing
# Stage 1: Builder - Install dependencies
FROM python:3.10-slim AS builder

WORKDIR /build

# Install Poetry for dependency management
RUN pip install --no-cache-dir poetry==1.7.1

# Copy dependency files
COPY pyproject.toml poetry.lock ./

# Export dependencies to requirements.txt (avoids Poetry in runtime image)
RUN poetry export -f requirements.txt --output requirements.txt --without-hashes

################################################################################
# Stage 2: Runtime - Minimal production image
################################################################################
FROM python:3.10-slim

# Metadata labels
LABEL maintainer="sre-team@example.com"
LABEL description="Distributed Locust load testing container"
LABEL version="1.0.0"

# Create non-root user for security
RUN groupadd -r locust -g 1000 && \
    useradd -r -u 1000 -g locust -m -s /bin/bash locust

WORKDIR /app

# Copy requirements from builder stage
COPY --from=builder /build/requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt && \
    rm requirements.txt

# Copy application code
COPY --chown=locust:locust locust/ ./locust/
COPY --chown=locust:locust locustfile.py ./
COPY --chown=locust:locust docker/entrypoint.sh /entrypoint.sh

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

# Switch to non-root user
USER locust

# Expose Locust ports
# 8089: Web UI
# 5557: Master-worker communication
EXPOSE 8089 5557

# Health check (pings Locust web interface)
# Only works for master mode; workers will rely on process check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8089', timeout=5).read()" 2>/dev/null || exit 1

# Use entrypoint script to handle master vs. worker mode
ENTRYPOINT ["/entrypoint.sh"]
