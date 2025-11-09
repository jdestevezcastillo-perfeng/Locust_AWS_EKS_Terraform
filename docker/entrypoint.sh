#!/bin/bash
set -e

################################################################################
# Locust Entrypoint Script
# Supports both master and worker modes via environment variables
################################################################################

# Configuration from environment variables
LOCUST_MODE=${LOCUST_MODE:-master}
TARGET_HOST=${TARGET_HOST:-https://jsonplaceholder.typicode.com}
LOCUST_FILE=${LOCUST_FILE:-locustfile.py}
MASTER_HOST=${MASTER_HOST:-locust-master}
MASTER_PORT=${MASTER_PORT:-5557}
LOG_LEVEL=${LOG_LEVEL:-INFO}

echo "=============================================="
echo "  Locust Load Testing Container"
echo "=============================================="
echo "Mode:        ${LOCUST_MODE}"
echo "Target Host: ${TARGET_HOST}"
echo "Locust File: ${LOCUST_FILE}"
echo "Log Level:   ${LOG_LEVEL}"
echo "=============================================="

if [ "$LOCUST_MODE" = "master" ]; then
    echo "Starting Locust Master..."
    echo "Web UI will be available on port 8089"
    echo "Prometheus metrics will be available on port 8089/metrics"
    echo "Workers should connect to: ${HOSTNAME}:${MASTER_PORT}"

    exec locust \
        -f ${LOCUST_FILE} \
        --master \
        --master-bind-port=${MASTER_PORT} \
        --host=${TARGET_HOST} \
        --web-host=0.0.0.0 \
        --web-port=8089 \
        --loglevel=${LOG_LEVEL}

elif [ "$LOCUST_MODE" = "worker" ]; then
    echo "Starting Locust Worker..."
    echo "Connecting to master at: ${MASTER_HOST}:${MASTER_PORT}"

    # Add a small delay to ensure master is ready
    sleep 2

    exec locust \
        -f ${LOCUST_FILE} \
        --worker \
        --master-host=${MASTER_HOST} \
        --master-port=${MASTER_PORT} \
        --loglevel=${LOG_LEVEL}

else
    echo "ERROR: LOCUST_MODE must be 'master' or 'worker'"
    echo "Current value: ${LOCUST_MODE}"
    exit 1
fi
