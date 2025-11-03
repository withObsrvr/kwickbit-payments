# Installation and Setup

## Project Structure

```
kwickbit-payments/
├── config/
│   ├── kwickbit-payments-full.yaml    # Full config with PostgreSQL + Pub/Sub
│   └── kwickbit-payments-test.yaml    # Test config (PostgreSQL only)
├── setup/
│   ├── create_topics.py               # Create Pub/Sub topics
│   └── requirements.txt               # Python dependencies
├── docker-compose.yml                 # Local dev services
├── flake.nix                          # Nix development environment
├── flake.lock                         # Nix dependencies lock file
├── README.md                          # Comprehensive documentation
└── INSTALL.md                         # This file

Parent directory (cdp-pipeline-workflow):
../cdp-pipeline-workflow/
├── cdp-pipeline-workflow              # Binary (must be built)
└── [source code and components]
```

## Prerequisites

This project requires the `cdp-pipeline-workflow` binary from the parent repository.

### Option 1: Using Nix (Recommended for NixOS)

Nix will handle all dependencies automatically:

```bash
# Enter development environment
nix develop
```

The Nix flake provides these commands:
- `setup-local` - Start PostgreSQL and Pub/Sub emulator
- `run-kwickbit` - Run the indexer
- `query-payments` - Query PostgreSQL for payment data
- `pull-messages` - Pull messages from Pub/Sub
- `teardown-local` - Stop all services

### Option 2: Manual Installation

Required tools:
- Docker & Docker Compose
- PostgreSQL client (`psql`)
- Python 3 with `google-cloud-pubsub`
- Google Cloud SDK (`gcloud`)
- Built `cdp-pipeline-workflow` binary

## Building the CDP Pipeline Binary

The kwickbit-payments indexer requires the `cdp-pipeline-workflow` binary from the parent repository.

### Build with Nix (Recommended):

```bash
cd ../cdp-pipeline-workflow
nix build
# Binary will be at: result/bin/cdp-pipeline-workflow

# Or copy to project root:
cp result/bin/cdp-pipeline-workflow .
```

### Build with Go:

```bash
cd ../cdp-pipeline-workflow
CGO_ENABLED=1 go build -o cdp-pipeline-workflow
```

**Note:** Building with Go requires:
- Go 1.23+
- CGO enabled
- System libraries: libzmq3-dev, libczmq-dev, libsodium-dev, DuckDB, Arrow

## Quick Start

### 1. Build CDP Pipeline Binary

```bash
cd ../cdp-pipeline-workflow
nix build
cp result/bin/cdp-pipeline-workflow .
cd ../kwickbit-payments
```

### 2. Start Local Services

Using Nix:
```bash
nix develop
setup-local
```

Or manually:
```bash
docker-compose up -d
export PUBSUB_EMULATOR_HOST="localhost:8085"
export PUBSUB_PROJECT_ID="local-dev-project"
python3 setup/create_topics.py
```

### 3. Set Environment Variables

```bash
export DB_PASSWORD="test"
export PUBSUB_PROJECT_ID="local-dev-project"
export PUBSUB_EMULATOR_HOST="localhost:8085"
```

### 4. Run the Indexer

Using Nix:
```bash
nix develop
run-kwickbit config/kwickbit-payments-full.yaml
```

Or manually:
```bash
../cdp-pipeline-workflow/cdp-pipeline-workflow -config config/kwickbit-payments-full.yaml
```

### 5. Query Data

Check PostgreSQL:
```bash
# With Nix
query-payments 10

# Or manually
docker exec -it kwickbit-postgres psql -U postgres -d kwickbit \
  -c "SELECT * FROM event_payments ORDER BY block_height DESC LIMIT 10;"
```

Check Pub/Sub messages:
```bash
# With Nix
pull-messages 10

# Or manually
gcloud pubsub subscriptions pull payments-sub \
  --auto-ack \
  --project=local-dev-project \
  --limit=10
```

## Troubleshooting

### Binary not found

```
❌ Error: CDP Pipeline binary not found at ../cdp-pipeline-workflow/cdp-pipeline-workflow
```

**Solution:** Build the binary first (see "Building the CDP Pipeline Binary" above)

### Docker not running

```
❌ Docker is not running. Please start Docker first.
```

**Solution:** Start Docker daemon:
```bash
sudo systemctl start docker
```

### Pub/Sub emulator not reachable

```bash
# Check if emulator is running
curl http://localhost:8085

# Check container logs
docker logs kwickbit-pubsub

# Restart services
docker-compose restart
```

### PostgreSQL connection failed

```bash
# Check if container is running
docker ps | grep postgres

# Test connection
docker exec -it kwickbit-postgres psql -U postgres -d kwickbit
```

## Production Deployment

For production deployment, see the **Production Deployment** section in README.md.

Key differences:
- Use real Google Cloud Pub/Sub (not emulator)
- Use managed PostgreSQL (Cloud SQL, RDS, etc.)
- Set proper credentials via environment variables
- Enable SSL for database connections

## Next Steps

See README.md for:
- Architecture details
- Database schema
- Example queries
- Configuration options
- Production deployment guide
