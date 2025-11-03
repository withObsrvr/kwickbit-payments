{
  description = "Kwickbit Payment Event Processor - Stellar smart contract event indexer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Python environment with Pub/Sub client
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          google-cloud-pubsub
        ]);

        # Path to cdp-pipeline-workflow binary (built from parent repo)
        cdpPipelinePath = ../cdp-pipeline-workflow;

        # Runtime dependencies
        runtimeDeps = with pkgs; [
          # Container tools
          docker
          docker-compose

          # Database tools
          postgresql

          # Python for setup scripts
          pythonEnv

          # Google Cloud SDK (for gcloud commands)
          google-cloud-sdk

          # Utilities
          curl
          jq
        ];

        # Run script for the indexer
        run-kwickbit = pkgs.writeShellScriptBin "run-kwickbit" ''
          set -e

          CONFIG_FILE="''${1:-config/kwickbit-payments-full.yaml}"

          # Check if CDP Pipeline binary exists
          CDP_BINARY="${cdpPipelinePath}/cdp-pipeline-workflow"
          if [ ! -f "$CDP_BINARY" ]; then
            echo "❌ Error: CDP Pipeline binary not found at $CDP_BINARY"
            echo "Please build it first:"
            echo "  cd ${cdpPipelinePath}"
            echo "  nix build"
            echo "  # or"
            echo "  CGO_ENABLED=1 go build -o cdp-pipeline-workflow"
            exit 1
          fi

          if [ ! -f "$CONFIG_FILE" ]; then
            echo "❌ Error: Config file not found: $CONFIG_FILE"
            exit 1
          fi

          # Check required environment variables
          if [ -z "$DB_PASSWORD" ]; then
            echo "❌ Error: DB_PASSWORD environment variable not set"
            exit 1
          fi

          if [ -z "$PUBSUB_PROJECT_ID" ]; then
            echo "❌ Error: PUBSUB_PROJECT_ID environment variable not set"
            exit 1
          fi

          echo "🚀 Starting Kwickbit Payment Indexer"
          echo "   Binary: $CDP_BINARY"
          echo "   Config: $CONFIG_FILE"
          echo "   Pub/Sub Project: $PUBSUB_PROJECT_ID"

          if [ -n "$PUBSUB_EMULATOR_HOST" ]; then
            echo "   Using Pub/Sub emulator at: $PUBSUB_EMULATOR_HOST"
          fi

          echo ""

          "$CDP_BINARY" -config "$CONFIG_FILE"
        '';

        # Setup script for local environment
        setup-local = pkgs.writeShellScriptBin "setup-local" ''
          set -e

          echo "🔧 Setting up local development environment"
          echo ""

          # Check Docker
          if ! ${pkgs.docker}/bin/docker info > /dev/null 2>&1; then
            echo "❌ Docker is not running. Please start Docker first."
            exit 1
          fi

          echo "✓ Docker is running"

          # Start Docker Compose
          echo ""
          echo "Starting PostgreSQL and Pub/Sub emulator..."
          ${pkgs.docker-compose}/bin/docker-compose up -d

          # Wait for services
          echo ""
          echo "Waiting for services to be ready..."
          sleep 5

          # Check PostgreSQL
          until ${pkgs.docker}/bin/docker exec kwickbit-postgres ${pkgs.postgresql}/bin/pg_isready -U postgres > /dev/null 2>&1; do
            echo "  Waiting for PostgreSQL..."
            sleep 2
          done
          echo "✓ PostgreSQL is ready"

          # Check Pub/Sub emulator
          until ${pkgs.curl}/bin/curl -s http://localhost:8085 > /dev/null 2>&1; do
            echo "  Waiting for Pub/Sub emulator..."
            sleep 2
          done
          echo "✓ Pub/Sub emulator is ready"

          # Create Pub/Sub topic
          echo ""
          echo "Creating Pub/Sub topic..."
          export PUBSUB_EMULATOR_HOST="localhost:8085"
          export PUBSUB_PROJECT_ID="local-dev-project"
          ${pythonEnv}/bin/python3 setup/create_topics.py

          echo ""
          echo "✅ Local environment is ready!"
          echo ""
          echo "Environment variables to export:"
          echo "  export DB_PASSWORD=\"test\""
          echo "  export PUBSUB_PROJECT_ID=\"local-dev-project\""
          echo "  export PUBSUB_EMULATOR_HOST=\"localhost:8085\""
          echo ""
          echo "Run the indexer:"
          echo "  run-kwickbit config/kwickbit-payments-full.yaml"
          echo ""
        '';

        # Teardown script
        teardown-local = pkgs.writeShellScriptBin "teardown-local" ''
          echo "🧹 Stopping local environment..."
          ${pkgs.docker-compose}/bin/docker-compose down
          echo "✓ Done"
        '';

        # Query script for checking data
        query-payments = pkgs.writeShellScriptBin "query-payments" ''
          LIMIT="''${1:-10}"

          echo "📊 Querying last $LIMIT payments from PostgreSQL..."
          ${pkgs.docker}/bin/docker exec -i kwickbit-postgres \
            ${pkgs.postgresql}/bin/psql -U postgres -d kwickbit -c \
            "SELECT id, payment_id, amount, merchant_id, block_height
             FROM event_payments
             ORDER BY block_height DESC
             LIMIT $LIMIT;"
        '';

        # Pull messages from Pub/Sub
        pull-messages = pkgs.writeShellScriptBin "pull-messages" ''
          LIMIT="''${1:-10}"

          if [ -z "$PUBSUB_EMULATOR_HOST" ]; then
            export PUBSUB_EMULATOR_HOST="localhost:8085"
          fi

          if [ -z "$PUBSUB_PROJECT_ID" ]; then
            export PUBSUB_PROJECT_ID="local-dev-project"
          fi

          echo "📬 Pulling last $LIMIT messages from Pub/Sub..."
          ${pkgs.google-cloud-sdk}/bin/gcloud pubsub subscriptions pull payments-sub \
            --auto-ack \
            --project="$PUBSUB_PROJECT_ID" \
            --limit="$LIMIT"
        '';

      in
      {
        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = runtimeDeps ++ [
            run-kwickbit
            setup-local
            teardown-local
            query-payments
            pull-messages
          ];

          shellHook = ''
            echo "🚀 Kwickbit Payment Event Processor"
            echo ""
            echo "Available commands:"
            echo "  setup-local      - Start PostgreSQL + Pub/Sub emulator"
            echo "  teardown-local   - Stop local services"
            echo "  run-kwickbit     - Run the indexer (requires env vars)"
            echo "  query-payments   - Query payments from PostgreSQL"
            echo "  pull-messages    - Pull messages from Pub/Sub"
            echo ""
            echo "Quick start:"
            echo "  1. setup-local"
            echo "  2. export DB_PASSWORD=\"test\""
            echo "  3. export PUBSUB_PROJECT_ID=\"local-dev-project\""
            echo "  4. export PUBSUB_EMULATOR_HOST=\"localhost:8085\""
            echo "  5. run-kwickbit"
            echo ""
            echo "Documentation: See README.md for detailed instructions"
            echo ""

            # Set custom prompt
            export PS1="\[\033[1;35m\][kwickbit]\[\033[0m\] \[\033[1;32m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ "
          '';
        };

        # Package outputs
        packages = {
          run-kwickbit = run-kwickbit;
          setup-local = setup-local;
          teardown-local = teardown-local;
          query-payments = query-payments;
          pull-messages = pull-messages;
        };

        # Formatter for `nix fmt`
        formatter = pkgs.nixpkgs-fmt;
      });
}
