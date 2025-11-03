#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting Kwickbit Payment Indexer - Local Development${NC}\n"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Start Docker Compose services
echo -e "${GREEN}1. Starting PostgreSQL and Pub/Sub emulator...${NC}"
cd "$(dirname "$0")"
docker-compose up -d

# Wait for services to be ready
echo -e "${GREEN}2. Waiting for services to be ready...${NC}"
sleep 5

# Check PostgreSQL
until docker exec kwickbit-postgres pg_isready -U postgres > /dev/null 2>&1; do
    echo "   Waiting for PostgreSQL..."
    sleep 2
done
echo -e "   ✓ PostgreSQL is ready"

# Check Pub/Sub emulator
until curl -s http://localhost:8085 > /dev/null 2>&1; do
    echo "   Waiting for Pub/Sub emulator..."
    sleep 2
done
echo -e "   ✓ Pub/Sub emulator is ready"

# Set environment variables for Pub/Sub emulator
export PUBSUB_EMULATOR_HOST="localhost:8085"
export PUBSUB_PROJECT_ID="local-dev-project"

# Create Pub/Sub topic
echo -e "${GREEN}3. Creating Pub/Sub topic...${NC}"
if command -v python3 &> /dev/null; then
    # Check if google-cloud-pubsub is installed
    if python3 -c "import google.cloud.pubsub_v1" 2>/dev/null; then
        python3 setup/create_topics.py
    else
        echo -e "${YELLOW}   Installing google-cloud-pubsub...${NC}"
        python3 -m pip install -q google-cloud-pubsub==2.18.4
        python3 setup/create_topics.py
    fi
else
    echo -e "${YELLOW}⚠️  Python 3 not found. Skipping topic creation.${NC}"
    echo -e "${YELLOW}   You can create the topic manually or install Python 3.${NC}"
fi

echo -e "\n${GREEN}✓ Local environment is ready!${NC}\n"

# Display connection info
echo -e "${BLUE}Connection Information:${NC}"
echo -e "  PostgreSQL:"
echo -e "    Host: localhost:5432"
echo -e "    Database: kwickbit"
echo -e "    Username: postgres"
echo -e "    Password: test"
echo -e ""
echo -e "  Pub/Sub Emulator:"
echo -e "    Host: localhost:8085"
echo -e "    Project ID: local-dev-project"
echo -e "    Topic: payments"
echo -e ""

# Display environment variables to export
echo -e "${BLUE}Environment Variables (copy and paste):${NC}"
echo -e "  export DB_PASSWORD=\"test\""
echo -e "  export PUBSUB_PROJECT_ID=\"local-dev-project\""
echo -e "  export PUBSUB_EMULATOR_HOST=\"localhost:8085\""
echo -e ""

# Display run command
echo -e "${BLUE}Run the indexer:${NC}"
echo -e "  cd ../../"
echo -e "  ./cdp-pipeline-workflow -config config/kwickbit-payments-full.yaml"
echo -e ""

# Display how to view data
echo -e "${BLUE}View Data:${NC}"
echo -e "  PostgreSQL:"
echo -e "    docker exec -it kwickbit-postgres psql -U postgres -d kwickbit -c 'SELECT * FROM event_payments;'"
echo -e ""
echo -e "  Pub/Sub Messages:"
echo -e "    gcloud pubsub subscriptions pull payments-sub --auto-ack --project=local-dev-project --limit=10"
echo -e ""

# Display shutdown command
echo -e "${BLUE}Shutdown:${NC}"
echo -e "  docker-compose down"
echo -e "  # or to remove volumes:"
echo -e "  docker-compose down -v"
echo -e ""
