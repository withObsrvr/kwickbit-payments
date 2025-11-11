#!/bin/bash
set -e

# Kwickbit Payment Indexer - Docker Run Script
# This script runs the indexer using Docker without requiring Nix or the parent repo

# Default values
CONFIG_FILE="${CONFIG_FILE:-config/kwickbit-payments-full.yaml}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5434}"
DB_PASSWORD="${DB_PASSWORD:-test}"
DB_DATABASE="${DB_DATABASE:-kwickbit}"
PUBSUB_PROJECT_ID="${PUBSUB_PROJECT_ID:-local-dev-project}"
PUBSUB_EMULATOR_HOST="${PUBSUB_EMULATOR_HOST:-localhost:8085}"

echo "Running Kwickbit Payment Indexer with Docker..."
echo "Config: $CONFIG_FILE"
echo "DB: $DB_HOST:$DB_PORT/$DB_DATABASE"
echo "Pub/Sub Emulator: $PUBSUB_EMULATOR_HOST"
echo ""

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    echo "Please create a config file or set CONFIG_FILE environment variable"
    exit 1
fi

# Run the indexer
docker run --rm \
  --network host \
  -v "$(pwd)/config:/app/config" \
  -e DB_HOST="$DB_HOST" \
  -e DB_PORT="$DB_PORT" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e DB_DATABASE="$DB_DATABASE" \
  -e PUBSUB_PROJECT_ID="$PUBSUB_PROJECT_ID" \
  -e PUBSUB_EMULATOR_HOST="$PUBSUB_EMULATOR_HOST" \
  withobsrvr/obsrvr-flow-pipeline:latest \
  /app/bin/cdp-pipeline-workflow -config "/app/config/$(basename "$CONFIG_FILE")"
