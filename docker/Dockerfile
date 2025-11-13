################################################################################
# Runtime - Python image for Locust
################################################################################
FROM python:3.13-slim

# Metadata labels
LABEL maintainer="sre-team@example.com"
LABEL description="Distributed Locust load testing container"
LABEL version="1.0.0"

# Create non-root user for security
RUN groupadd -r locust -g 1000 && \
    useradd -r -u 1000 -g locust -m -s /bin/bash locust

WORKDIR /app

# Install Python dependencies
# Locust + Prometheus metrics exporter
RUN pip install --no-cache-dir 'locust>=2.42.2,<3.0.0' 'prometheus-client>=0.23.1,<1.0.0'

# Copy application code
COPY --chown=locust:locust tests/ ./tests/
COPY --chown=locust:locust docker/entrypoint.sh /entrypoint.sh

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

# Switch to non-root user
USER locust

# Expose Locust ports
# 8089: Web UI
# 5557: Master-worker communication
# 8090: Prometheus metrics
EXPOSE 8089 5557 8090

# Health check (pings Locust web interface)
# Only works for master mode; workers will rely on process check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8089', timeout=5).read()" 2>/dev/null || exit 1

# Use entrypoint script to handle master vs. worker mode
ENTRYPOINT ["/entrypoint.sh"]
