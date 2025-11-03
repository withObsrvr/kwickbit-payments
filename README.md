# Kwickbit Payment Event Processor

Standalone indexer for Stellar smart contract payment events from Kwickbit's payment processor. Saves structured payment data to PostgreSQL and publishes to Google Pub/Sub.

## Overview

The pipeline processes contract events from Kwickbit's testnet payment processor contract (`CCQBTIFXJ6RE43YSQDGWNXBMVLBRKVBAIE3IE6225T4LLO374RNTPS5G`) and:

1. **Extracts** structured payment data (payment_id, token, amount, from, merchant, royalty_amount)
2. **Saves** to PostgreSQL with proper schema and foreign key relationships
3. **Publishes** to Google Pub/Sub topic for downstream processing

## Architecture

```
BufferedStorageSourceAdapter (GCS ledgers)
    ↓
ContractEvent Processor (decode events)
    ↓
ContractFilter (filter by contract ID)
    ↓
EventPaymentExtractor (NEW - extract payment fields)
    ↓
    ├──→ SaveEventPaymentToPostgreSQL (NEW - save to database)
    └──→ PublishToGooglePubSub (NEW - publish to topic)
```

## Quick Start

### Option A: Using Nix Flake (Recommended for NixOS)

The easiest way to run the indexer on NixOS:

```bash
# Enter the Nix development environment
nix develop

# Start local PostgreSQL and Pub/Sub emulator
setup-local

# In another terminal (or after setup completes)
nix develop
export DB_PASSWORD="test"
export PUBSUB_PROJECT_ID="local-dev-project"
export PUBSUB_EMULATOR_HOST="localhost:8085"

# Run the indexer
run-kwickbit config/kwickbit-payments-full.yaml

# Query results
query-payments 10           # View last 10 payments in PostgreSQL
pull-messages 10            # Pull last 10 messages from Pub/Sub

# Cleanup
teardown-local
```

**Available Nix Commands:**
- `setup-local` - Start PostgreSQL + Pub/Sub emulator with Docker Compose
- `run-kwickbit [config]` - Run the indexer with specified config
- `query-payments [limit]` - Query payments from PostgreSQL
- `pull-messages [limit]` - Pull messages from Pub/Sub subscription
- `teardown-local` - Stop all local services

### Option B: Manual Setup

#### 1. Prerequisites

- PostgreSQL 16+
- Google Cloud Pub/Sub (or emulator for local testing)
- Go 1.23+
- Built `cdp-pipeline-workflow` binary (from parent repo)

### 2. Environment Variables

```bash
# Database
export DB_PASSWORD="your-password"
export DB_HOST="localhost"          # Optional, defaults to localhost
export DB_DATABASE="kwickbit"       # Optional, defaults to postgres

# Google Pub/Sub
export PUBSUB_PROJECT_ID="your-project-id"
export GCLOUD_PUBSUB_PUBLISHER_SERVICE_ACCOUNT_KEY='{"type": "service_account", ...}'

# Or use credentials file instead:
# export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"

# For local testing with Pub/Sub emulator:
export PUBSUB_EMULATOR_HOST="localhost:8085"
```

#### 3. Run Locally with Docker

**Using Docker Compose:**

```bash
docker-compose up -d
```

This starts:
- PostgreSQL on port 5434 (mapped from container's internal 5432)
- Google Pub/Sub emulator on port 8085

#### 4. Create Pub/Sub Topic (Local Emulator)

```bash
# Set emulator host
export PUBSUB_EMULATOR_HOST="localhost:8085"
export PUBSUB_PROJECT_ID="local-dev-project"

# Create topic
python3 setup/create_topics.py
```

#### 5. Run the Indexer

```bash
# Set environment variables
export DB_PASSWORD="test"
export PUBSUB_PROJECT_ID="local-dev-project"
export PUBSUB_EMULATOR_HOST="localhost:8085"

# Run the pipeline (use binary from parent repo)
../cdp-pipeline-workflow/cdp-pipeline-workflow -config config/kwickbit-payments-full.yaml
```

Expected output:
```
Processing ledger 1281924...
EventPaymentExtractor: Extracted payment_id=0x71b203759c071753..., amount=100000, merchant=GAQRE...
SaveEventPaymentToPostgreSQL: Saved payment id=1281925-86e3bb96-2, payment_id=0x71b203759c071753...
PublishToGooglePubSub: Published payment_id=0x71b203759c071753..., messageID=12345
Processing ledger 1281925...
...
```

## Database Schema

### Accounts Table

```sql
CREATE TABLE accounts (
    id TEXT PRIMARY KEY  -- Stellar address (account or contract)
);
```

### Event Payments Table

```sql
CREATE TABLE event_payments (
    id TEXT PRIMARY KEY,                              -- Format: {ledger}-{txhash[:8]}-{eventindex}
    payment_id TEXT NOT NULL,                         -- Hex string with 0x prefix
    token_id TEXT NOT NULL REFERENCES accounts(id),   -- Token contract address
    amount BIGINT NOT NULL,                           -- Payment amount
    from_id TEXT NOT NULL REFERENCES accounts(id),    -- Sender account address
    merchant_id TEXT NOT NULL REFERENCES accounts(id), -- Merchant account address
    royalty_amount BIGINT NOT NULL,                   -- Royalty amount
    tx_hash TEXT NOT NULL,                            -- Transaction hash
    block_height BIGINT NOT NULL,                     -- Ledger sequence
    block_timestamp TIMESTAMP NOT NULL                -- Ledger close time
);

-- Indexes for fast queries
CREATE INDEX idx_payment_id ON event_payments(payment_id);
CREATE INDEX idx_token_id ON event_payments(token_id);
CREATE INDEX idx_merchant_id ON event_payments(merchant_id);
CREATE INDEX idx_tx_hash ON event_payments(tx_hash);
CREATE INDEX idx_block_height ON event_payments(block_height);
CREATE INDEX idx_block_timestamp ON event_payments(block_timestamp);
```

## Example Queries

### Get all payments

```sql
SELECT * FROM event_payments ORDER BY block_height DESC;
```

### Get payments for a specific merchant

```sql
SELECT
    payment_id,
    amount,
    royalty_amount,
    from_id,
    block_height,
    block_timestamp
FROM event_payments
WHERE merchant_id = 'GAQREXOUVV6XLQAWHZ3CMMZPMQJ5QDIWU2DWP4CDDTTIFHUPZPJEFFRJ'
ORDER BY block_height DESC;
```

### Get payment history for an account (sent + received)

```sql
-- Payments sent
SELECT
    ep.*,
    'sent' as direction
FROM event_payments ep
WHERE ep.from_id = 'GACITQZ7I4CQU5YLMWV4F274NVZJ2RSP6NISYJSYBK47D2IONAL26MBH'

UNION ALL

-- Payments received
SELECT
    ep.*,
    'received' as direction
FROM event_payments ep
WHERE ep.merchant_id = 'GACITQZ7I4CQU5YLMWV4F274NVZJ2RSP6NISYJSYBK47D2IONAL26MBH'

ORDER BY block_height DESC;
```

### Get total payment volume by merchant

```sql
SELECT
    merchant_id,
    COUNT(*) as payment_count,
    SUM(amount) as total_amount,
    SUM(royalty_amount) as total_royalties
FROM event_payments
GROUP BY merchant_id
ORDER BY total_amount DESC;
```

## Pub/Sub Message Format

Messages published to the `payments` topic:

```json
{
  "id": "1281925-86e3bb96-2",
  "payment_id": "0x71b203759c071753fbbb8e6c709327ce0961aadf2e84ef4bf6b25dae12a40047",
  "token_id": "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA",
  "amount": 100000,
  "from_id": "GACITQZ7I4CQU5YLMWV4F274NVZJ2RSP6NISYJSYBK47D2ONAL26MBH",
  "merchant_id": "GAQREXOUVV6XLQAWHZ3CMMZPMQJ5QDIWU2DWP4CDDTTIFHUPZPJEFFRJ",
  "royalty_amount": 2000,
  "tx_hash": "86e3bb968c2c06dc4cc3add8b43c477ef5945d6b77be3a9d5cc46440fd2100fa",
  "block_height": 1281925,
  "block_timestamp": "2025-10-27T23:50:47Z"
}
```

**Message Attributes:**
- `event_type`: "payment"
- `block_height`: Ledger sequence as string
- `payment_id`: Payment ID hex string

## Testing with Pub/Sub Emulator

### Create Subscriber to Receive Messages

```bash
# Create subscription
gcloud pubsub subscriptions create payments-sub \
  --topic=payments \
  --project=local-dev-project

# Pull messages
gcloud pubsub subscriptions pull payments-sub \
  --auto-ack \
  --project=local-dev-project \
  --limit=10
```

### Or use Push Subscription

```python
# server.py - Simple Flask app to receive push notifications
from flask import Flask, request

app = Flask(__name__)

@app.route('/payments', methods=['POST'])
def receive_payment():
    data = request.get_json()
    print(f"Received payment: {data}")
    return 'OK', 200

if __name__ == '__main__':
    app.run(port=3000)
```

Create push subscription:
```bash
python3 setup/create_topics.py  # Creates topic + push subscription
```

## Configuration Options

### EventPaymentExtractor Processor

```yaml
- type: EventPaymentExtractor
  config:
    network_passphrase: "Test SDF Network ; September 2015"
```

**What it does:**
- Filters for "payment" event types
- Extracts: payment_id, token, amount, from, merchant, royalty_amount
- Converts payment_id bytes to hex string with "0x" prefix
- Adds block metadata: txHash, blockHeight, blockTimestamp

### SaveEventPaymentToPostgreSQL Consumer

```yaml
- type: SaveEventPaymentToPostgreSQL
  config:
    host: "localhost"
    port: 5434
    database: "kwickbit"
    username: "postgres"
    password: "${DB_PASSWORD}"    # From env var
    sslmode: "disable"
    max_open_conns: 10
    max_idle_conns: 5
```

**Environment variables:**
- `DB_PASSWORD` - Database password (required)
- `DB_HOST` - Database host (optional, default: localhost)
- `DB_DATABASE` - Database name (optional, default: postgres)

### PublishToGooglePubSub Consumer

```yaml
- type: PublishToGooglePubSub
  config:
    project_id: "${PUBSUB_PROJECT_ID}"
    topic_id: "payments"
    # credentials_json: "${GCLOUD_PUBSUB_PUBLISHER_SERVICE_ACCOUNT_KEY}"
    # credentials_file: "/path/to/service-account.json"
```

**Environment variables:**
- `PUBSUB_PROJECT_ID` - GCP project ID (required)
- `GCLOUD_PUBSUB_PUBLISHER_SERVICE_ACCOUNT_KEY` - JSON credentials as string
- `GOOGLE_APPLICATION_CREDENTIALS` - Path to credentials file
- `PUBSUB_EMULATOR_HOST` - Emulator host (e.g., "localhost:8085") for local testing

## Troubleshooting

### No data appearing in PostgreSQL

1. Check the pipeline logs for errors
2. Verify the contract ID matches: `CCQBTIFXJ6RE43YSQDGWNXBMVLBRKVBAIE3IE6225T4LLO374RNTPS5G`
3. Check the ledger range has payment events
4. Verify database connection: `psql -h localhost -U postgres -d kwickbit`

### Pub/Sub authentication errors

1. For local testing, make sure `PUBSUB_EMULATOR_HOST` is set
2. For cloud, verify credentials:
   ```bash
   # Test credentials
   gcloud auth application-default print-access-token
   ```
3. Make sure service account has `pubsub.publisher` role

### Database connection failed

```bash
# Test PostgreSQL connection
psql -h localhost -p 5434 -U postgres -d kwickbit

# Check if container is running
docker ps | grep postgres
```

### Pub/Sub emulator not reachable

```bash
# Check if emulator is running
curl http://localhost:8085

# Check container logs
docker logs kwickbit-pubsub
```

## Production Deployment

### Use Google Cloud Pub/Sub

1. Create topic in GCP Console or via CLI:
```bash
gcloud pubsub topics create payments --project=your-project-id
```

2. Create service account with `pubsub.publisher` role:
```bash
gcloud iam service-accounts create kwickbit-indexer \
  --display-name="Kwickbit Indexer"

gcloud projects add-iam-policy-binding your-project-id \
  --member="serviceAccount:kwickbit-indexer@your-project-id.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher"

gcloud iam service-accounts keys create credentials.json \
  --iam-account=kwickbit-indexer@your-project-id.iam.gserviceaccount.com
```

3. Run with production credentials:
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/credentials.json"
export PUBSUB_PROJECT_ID="your-project-id"
unset PUBSUB_EMULATOR_HOST  # Remove emulator host

# With Nix:
nix develop
run-kwickbit config/kwickbit-payments-full.yaml

# Or use binary directly:
../cdp-pipeline-workflow/cdp-pipeline-workflow -config config/kwickbit-payments-full.yaml
```

### Use Managed PostgreSQL

Update config for Cloud SQL or managed database:

```yaml
- type: SaveEventPaymentToPostgreSQL
  config:
    host: "your-db-instance.region.gcp.cloud.google.com"
    port: 5432
    database: "kwickbit-prod"
    username: "kwickbit"
    password: "${DB_PASSWORD}"
    sslmode: "require"  # Enable SSL for production
```

## Next Steps

- [ ] Add more contract addresses to filter
- [ ] Implement continuous mode for real-time indexing
- [ ] Add monitoring and alerting
- [ ] Set up dead letter queue for failed Pub/Sub publishes
- [ ] Add retries with exponential backoff for transient failures

## Support

For issues or questions:
- Check the troubleshooting section above
- Review pipeline logs for error messages
- Verify environment variables are set correctly
