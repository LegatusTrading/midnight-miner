.PHONY: help init start stop status backup local-help

# Default target
help:
	@echo "Midnight Miner - VPS and Local Management"
	@echo ""
	@echo "=== VPS Mode ==="
	@echo "Prerequisites: SSH key access to root@<hostname>"
	@echo ""
	@echo "Usage: make <target>-<host>"
	@echo ""
	@echo "Targets:"
	@echo "  init-<host>   - Install mining software on VPS (runs as root)"
	@echo "  start-<host>  - Start mining process"
	@echo "  stop-<host>   - Stop mining process"
	@echo "  status-<host> - Show mining status and save to status.md"
	@echo "  status-all    - Show summary status for all VPSs"
	@echo "  backup-<host> - Backup wallets and status to local data/ folder"
	@echo ""
	@echo "Example:"
	@echo "  make init-v01"
	@echo "  make start-v01"
	@echo "  make status-v01"
	@echo ""
	@echo "=== Local Mode ==="
	@echo "Run miner on this machine (no VPS required)"
	@echo ""
	@echo "Setup:"
	@echo "  make setup-local        - Complete setup (env + HD wallet + import)"
	@echo "  make generate-hd-wallet - Generate HD wallet only"
	@echo "  make import-hd-wallet   - Import HD wallet to miner format"
	@echo "  make init-local         - Setup environment only"
	@echo ""
	@echo "Mining:"
	@echo "  make start-local   - Start mining"
	@echo "  make stop-local    - Stop mining"
	@echo "  make restart-local - Restart mining"
	@echo ""
	@echo "Monitoring:"
	@echo "  make status-local  - Show status snapshot"
	@echo "  make watch-local   - Live filtered logs (hash rate, solutions)"
	@echo "  make monitor-local - Auto-refreshing status (requires 'watch')"
	@echo "  make events-local  - Show recent events summary"
	@echo "  make logs-local    - Tail full logs"
	@echo ""
	@echo "Info:"
	@echo "  make wallets-local - Show wallet addresses"
	@echo "  make verify-local  - Verify HD wallet addresses match"
	@echo ""
	@echo "Config files are in config/<host>.conf"

# Load host configuration
load-config-%:
	@if [ ! -f "config/$*.conf" ]; then \
		echo "Error: config/$*.conf not found"; \
		echo "Create it from config/v01.conf.example"; \
		exit 1; \
	fi

# Get config values (source the config file)
get-hostname-%: load-config-%
	@. config/$*.conf && echo $$HOSTNAME

get-datadir-%: load-config-%
	@. config/$*.conf && echo $$DATA_DIR

# VPS Mining Setup
init-%: load-config-%
	@echo "=== Setting up mining on VPS: $* ==="
	@HOSTNAME=$$($(MAKE) -s get-hostname-$*); \
	echo "Target: root@$$HOSTNAME"; \
	echo ""; \
	echo "Installing dependencies on $$HOSTNAME..."; \
	ssh root@$$HOSTNAME "apt update && apt install -y python3.12-venv python3-pip build-essential"; \
	echo ""; \
	echo "Creating mining directory..."; \
	ssh root@$$HOSTNAME "mkdir -p /root/midnight-miner"; \
	echo ""; \
	echo "Uploading miner code..."; \
	rsync -avz \
		--exclude='.git' \
		--exclude='.venv' \
		--exclude='venv' \
		--exclude='*.log' \
		--exclude='wallets.json' \
		--exclude='balances.json' \
		--exclude='challenges.json' \
		--exclude='config' \
		--exclude='data' \
		--exclude='vps' \
		. root@$$HOSTNAME:/root/midnight-miner/; \
	echo ""; \
	echo "Installing Python dependencies..."; \
	ssh root@$$HOSTNAME "cd /root/midnight-miner && python3 -m venv .venv && source .venv/bin/activate && pip install -q -r requirements.txt"; \
	echo ""; \
	echo "Installing systemd service..."; \
	ssh root@$$HOSTNAME "bash -s" < scripts/install-service.sh; \
	echo ""; \
	echo "Mining setup complete!"; \
	echo ""; \
	echo "Next step: make start-$*"

# Start Mining
start-%: load-config-%
	@echo "=== Starting mining on VPS: $* ==="
	@HOSTNAME=$$($(MAKE) -s get-hostname-$*); \
	ssh root@$$HOSTNAME "systemctl start midnight-miner"; \
	sleep 2; \
	ssh root@$$HOSTNAME "systemctl status midnight-miner --no-pager"; \
	echo ""; \
	echo "Mining started! Check logs with: make status-$*"

# Stop Mining
stop-%: load-config-%
	@echo "=== Stopping mining on VPS: $* ==="
	@HOSTNAME=$$($(MAKE) -s get-hostname-$*); \
	ssh root@$$HOSTNAME "systemctl stop midnight-miner"; \
	echo "Mining stopped!"

# Mining Status
status-%: load-config-%
	@echo "=== Mining status for VPS: $* ==="
	@HOSTNAME=$$($(MAKE) -s get-hostname-$*); \
	DATADIR=$$($(MAKE) -s get-datadir-$*); \
	mkdir -p $$DATADIR; \
	echo "Fetching status from $$HOSTNAME..."; \
	ssh root@$$HOSTNAME "bash -s" < scripts/get-status.sh > $$DATADIR/status.md; \
	echo ""; \
	cat $$DATADIR/status.md; \
	echo ""; \
	echo "Status saved to $$DATADIR/status.md"

# Check Mining Status (with mnemonic and wallet details)
check-%: load-config-%
	@HOSTNAME=$$($(MAKE) -s get-hostname-$*); \
	ssh root@$$HOSTNAME "bash -s $$HOSTNAME" < scripts/get-check-status.sh; \
	echo ""; \
	echo "Note: Crypto/Night columns show '-' due to Vercel bot protection."; \
	echo "      To see actual values, run locally:"; \
	echo "      ./scripts/fetch-wallet-stats.py data/$*/wallets.json"

# Backup Mining Data
backup-%: load-config-%
	@echo "=== Backing up mining data from VPS: $* ==="
	@HOSTNAME=$$($(MAKE) -s get-hostname-$*); \
	DATADIR=$$($(MAKE) -s get-datadir-$*); \
	TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	mkdir -p $$DATADIR; \
	echo "Downloading mnemonic..."; \
	scp -q root@$$HOSTNAME:/root/midnight-miner/hd-wallets/mnemonic.txt $$DATADIR/mnemonic-$$TIMESTAMP.txt 2>/dev/null || echo "  No mnemonic found"; \
	echo "Downloading wallets.json..."; \
	scp -q root@$$HOSTNAME:/root/midnight-miner/wallets.json $$DATADIR/wallets-$$TIMESTAMP.json 2>/dev/null || echo "  No wallets.json found"; \
	echo "Downloading balances.json..."; \
	scp -q root@$$HOSTNAME:/root/midnight-miner/balances.json $$DATADIR/balances-$$TIMESTAMP.json 2>/dev/null || echo "  No balances.json found"; \
	echo "Downloading challenges.json..."; \
	scp -q root@$$HOSTNAME:/root/midnight-miner/challenges.json $$DATADIR/challenges-$$TIMESTAMP.json 2>/dev/null || echo "  No challenges.json found"; \
	echo "Generating check report..."; \
	ssh root@$$HOSTNAME "bash -s $$HOSTNAME" < scripts/get-check-status.sh > $$DATADIR/check-$$TIMESTAMP.txt 2>/dev/null; \
	echo "Generating status report..."; \
	ssh root@$$HOSTNAME "bash -s" < scripts/get-status.sh > $$DATADIR/status-$$TIMESTAMP.md 2>/dev/null; \
	echo ""; \
	echo "Backup complete! Files saved to $$DATADIR/"; \
	ls -lh $$DATADIR/*-$$TIMESTAMP.*

# Catch-all pattern targets
init:
	@echo "Usage: make init-<host>"
	@echo "Example: make init-v01"

start:
	@echo "Usage: make start-<host>"
	@echo "Example: make start-v01"

stop:
	@echo "Usage: make stop-<host>"
	@echo "Example: make stop-v01"

status:
	@echo "Usage: make status-<host>"
	@echo "Example: make status-v01"

# All VPS status summary
status-all:
	@./status-all.sh

backup:
	@echo "Usage: make backup-<host>"
	@echo "Example: make backup-v01"

#==============================================================================
# Local Execution Targets
#==============================================================================

# Local configuration
LOCAL_VENV = .venv
LOCAL_PID_FILE = .miner.pid
LOCAL_LOG_FILE = miner.log
LOCAL_WORKERS = 24
LOCAL_WALLETS = 24
HD_WALLET_DIR = ./hd-wallets
NETWORK = mainnet

# Initialize local environment
init-local:
	@echo "=== Setting up local mining environment ==="
	@if [ ! -f "config/local.conf" ]; then \
		echo "Creating config/local.conf from example..."; \
		cp config/local.conf.example config/local.conf; \
	fi
	@echo ""
	@echo "Creating Python virtual environment..."
	@if [ ! -d "$(LOCAL_VENV)" ]; then \
		if python3 -m venv $(LOCAL_VENV) 2>/dev/null; then \
			echo "✓ Virtual environment created"; \
		else \
			echo "Note: python3-venv not available, using system Python"; \
			echo "If you want isolated environment, install: sudo apt install python3-venv"; \
		fi; \
	else \
		echo "✓ Virtual environment already exists"; \
	fi
	@echo ""
	@echo "Installing Python dependencies..."
	@if [ -d "$(LOCAL_VENV)" ] && [ -f "$(LOCAL_VENV)/bin/activate" ]; then \
		. $(LOCAL_VENV)/bin/activate && pip install -q --upgrade pip && pip install -q -r requirements.txt; \
	elif command -v pip3 >/dev/null 2>&1; then \
		echo "Installing to user directory..."; \
		pip3 install --user -q -r requirements.txt; \
	elif python3 -m pip --version >/dev/null 2>&1; then \
		echo "Installing to user directory..."; \
		python3 -m pip install --user -q -r requirements.txt; \
	else \
		echo "ERROR: Neither python3-venv nor pip is available!"; \
		echo ""; \
		echo "Please install one of:"; \
		echo "  sudo apt install python3-venv python3-pip  (Ubuntu/Debian)"; \
		echo "  sudo yum install python3-virtualenv python3-pip  (RedHat/CentOS)"; \
		echo ""; \
		exit 1; \
	fi
	@echo ""
	@echo "Setting up Cardano tools..."
	@if [ ! -f "lib/cardano-address" ] || [ ! -f "lib/cardano-cli" ]; then \
		echo "Downloading Cardano tools..."; \
		mkdir -p lib; \
		OS=$$(uname -s); \
		ARCH=$$(uname -m); \
		if [ ! -f "lib/cardano-address" ]; then \
			echo "  - cardano-address v4.0.1"; \
			if [ "$$OS" = "Darwin" ]; then \
				curl -sSL https://github.com/IntersectMBO/cardano-addresses/releases/download/4.0.1/cardano-address-4.0.1-macos.tar.gz -o lib/cardano-address.tar.gz; \
			else \
				curl -sSL https://github.com/IntersectMBO/cardano-addresses/releases/download/4.0.1/cardano-address-4.0.1-linux.tar.gz -o lib/cardano-address.tar.gz; \
			fi; \
			tar -xzf lib/cardano-address.tar.gz -C lib/; \
			rm lib/cardano-address.tar.gz; \
			chmod +x lib/cardano-address; \
			ln -sf lib/cardano-address cardano-address; \
		fi; \
		if [ ! -f "lib/cardano-cli" ]; then \
			echo "  - cardano-cli v10.13.1.0"; \
			if [ "$$OS" = "Darwin" ]; then \
				if [ "$$ARCH" = "arm64" ]; then \
					curl -sSL https://github.com/IntersectMBO/cardano-cli/releases/download/cardano-cli-10.13.1.0/cardano-cli-10.13.1.0-aarch64-darwin.tar.gz -o lib/cardano-cli.tar.gz; \
				else \
					curl -sSL https://github.com/IntersectMBO/cardano-cli/releases/download/cardano-cli-10.13.1.0/cardano-cli-10.13.1.0-x86_64-darwin.tar.gz -o lib/cardano-cli.tar.gz; \
				fi; \
			else \
				if [ "$$ARCH" = "x86_64" ]; then \
					curl -sSL https://github.com/IntersectMBO/cardano-cli/releases/download/cardano-cli-10.13.1.0/cardano-cli-10.13.1.0-x86_64-linux.tar.gz -o lib/cardano-cli.tar.gz; \
				elif [ "$$ARCH" = "aarch64" ]; then \
					curl -sSL https://github.com/IntersectMBO/cardano-cli/releases/download/cardano-cli-10.13.1.0/cardano-cli-10.13.1.0-aarch64-linux.tar.gz -o lib/cardano-cli.tar.gz; \
				else \
					echo "ERROR: Unsupported architecture: $$ARCH"; \
					exit 1; \
				fi; \
			fi; \
			tar -xzf lib/cardano-cli.tar.gz -C lib/; \
			rm lib/cardano-cli.tar.gz; \
			if [ "$$OS" = "Darwin" ]; then \
				chmod +x lib/cardano-cli-*-darwin; \
				mv lib/cardano-cli-*-darwin lib/cardano-cli; \
			else \
				chmod +x lib/cardano-cli-*-linux; \
				mv lib/cardano-cli-*-linux lib/cardano-cli; \
			fi; \
			ln -sf lib/cardano-cli cardano-cli; \
		fi; \
		echo "✓ Cardano tools installed"; \
	else \
		echo "✓ Cardano tools already installed"; \
	fi
	@echo ""
	@echo "Creating data directory..."
	@mkdir -p data/local
	@echo ""
	@echo "Checking for HD wallet..."
	@if [ ! -f "wallets.json" ]; then \
		echo ""; \
		echo "⚠️  No wallets.json found. You need to generate HD wallets first:"; \
		echo ""; \
		echo "  make generate-hd-wallet"; \
		echo ""; \
		echo "Or run the full setup:"; \
		echo "  make setup-local"; \
		echo ""; \
	else \
		echo "✓ Wallets found"; \
	fi
	@echo ""
	@echo "✓ Local environment ready!"
	@echo ""
	@if [ -f "wallets.json" ]; then \
		echo "Next step: make start-local"; \
	else \
		echo "Next step: make generate-hd-wallet  (or make setup-local for full setup)"; \
	fi

# Start local mining
start-local:
	@if [ -f "$(LOCAL_PID_FILE)" ] && kill -0 $$(cat $(LOCAL_PID_FILE)) 2>/dev/null; then \
		echo "Miner is already running (PID: $$(cat $(LOCAL_PID_FILE)))"; \
		exit 1; \
	fi
	@echo "=== Starting local mining ==="
	@echo "Starting miner with $(LOCAL_WORKERS) workers and $(LOCAL_WALLETS) wallets..."
	@if [ -d "$(LOCAL_VENV)" ]; then \
		nohup $(LOCAL_VENV)/bin/python3 miner.py --workers $(LOCAL_WORKERS) --wallets $(LOCAL_WALLETS) > $(LOCAL_LOG_FILE) 2>&1 & echo $$! > $(LOCAL_PID_FILE); \
	else \
		nohup python3 miner.py --workers $(LOCAL_WORKERS) --wallets $(LOCAL_WALLETS) > $(LOCAL_LOG_FILE) 2>&1 & echo $$! > $(LOCAL_PID_FILE); \
	fi
	@sleep 2
	@if [ -f "$(LOCAL_PID_FILE)" ] && kill -0 $$(cat $(LOCAL_PID_FILE)) 2>/dev/null; then \
		echo "✓ Mining started! (PID: $$(cat $(LOCAL_PID_FILE)))"; \
		echo ""; \
		echo "Check status: make status-local"; \
		echo "View logs:    make logs-local"; \
	else \
		echo "✗ Failed to start miner. Check logs: tail $(LOCAL_LOG_FILE)"; \
		rm -f $(LOCAL_PID_FILE); \
		exit 1; \
	fi

# Stop local mining
stop-local:
	@echo "=== Stopping local mining ==="
	@if [ ! -f "$(LOCAL_PID_FILE)" ]; then \
		echo "Miner is not running (no PID file found)"; \
		exit 0; \
	fi
	@PID=$$(cat $(LOCAL_PID_FILE)); \
	if kill -0 $$PID 2>/dev/null; then \
		echo "Stopping miner..."; \
		pkill -f "python3.*miner.py" && sleep 2 && echo "All miner processes killed"; \
		if kill -0 $$PID 2>/dev/null; then \
			echo "Force killing miner..."; \
			kill -9 $$PID; \
		fi; \
		rm -f $(LOCAL_PID_FILE); \
		echo "✓ Miner stopped"; \
	else \
		echo "Miner process not found, cleaning up PID file"; \
		rm -f $(LOCAL_PID_FILE); \
	fi

# Show local mining status
status-local:
	@echo "=== Local Mining Status ==="
	@echo ""
	@if [ -f "$(LOCAL_PID_FILE)" ] && kill -0 $$(cat $(LOCAL_PID_FILE)) 2>/dev/null; then \
		echo "Status: RUNNING (PID: $$(cat $(LOCAL_PID_FILE)))"; \
	else \
		echo "Status: STOPPED"; \
		rm -f $(LOCAL_PID_FILE) 2>/dev/null; \
	fi
	@echo ""
	@if [ -f "wallets.json" ]; then \
		WALLET_COUNT=$$(python3 -c "import json; print(len(json.load(open('wallets.json'))))"); \
		echo "Wallets: $$WALLET_COUNT loaded"; \
	else \
		echo "Wallets: None (will be generated on first run)"; \
	fi
	@echo ""
	@if [ -f "$(LOCAL_LOG_FILE)" ]; then \
		echo "Recent activity (last 20 structured log lines):"; \
		echo "---"; \
		grep -E "^(INFO:|ERROR:|WARNING:)" $(LOCAL_LOG_FILE) | tail -n 20; \
		echo "---"; \
		echo ""; \
		echo "Full logs: make logs-local | Events: make events-local"; \
	else \
		echo "No logs found yet"; \
	fi

# Tail local logs (with ANSI codes stripped)
logs-local:
	@if [ ! -f "$(LOCAL_LOG_FILE)" ]; then \
		echo "No log file found. Start the miner first: make start-local"; \
		exit 1; \
	fi
	@echo "Following local mining logs (Ctrl+C to exit)..."
	@echo "Note: ANSI color codes are stripped for cleaner output"
	@echo ""
	@tail -f $(LOCAL_LOG_FILE) | sed 's/\x1b\[[0-9;]*[mGKHJD]//g' | sed 's/\[[HJ][0-9;]*[mGKHJD]//g'

# Restart local mining
restart-local: stop-local
	@sleep 1
	@$(MAKE) start-local

# Generate HD wallet
generate-hd-wallet:
	@echo "=== Generating HD Wallet ==="
	@if [ -d "$(HD_WALLET_DIR)" ]; then \
		echo "⚠️  HD wallet directory already exists: $(HD_WALLET_DIR)"; \
		echo ""; \
		echo "Options:"; \
		echo "  1. Use existing wallet: make import-hd-wallet"; \
		echo "  2. Backup and regenerate: mv $(HD_WALLET_DIR) $(HD_WALLET_DIR).backup && make generate-hd-wallet"; \
		echo ""; \
		exit 1; \
	fi
	@echo ""
	@echo "Generating $(LOCAL_WALLETS) accounts for $(NETWORK)..."
	@./generate-hd-wallet.sh \
		--network $(NETWORK) \
		--accounts $(LOCAL_WALLETS) \
		--addresses 1 \
		--output $(HD_WALLET_DIR)
	@echo ""
	@echo "=== HD Wallet Generated Successfully! ==="
	@echo ""
	@echo "⚠️  CRITICAL: Backup your recovery phrase NOW!"
	@echo ""
	@echo "  cat $(HD_WALLET_DIR)/mnemonic.txt"
	@echo ""
	@echo "Next step: make import-hd-wallet"

# Import HD wallet to miner format
import-hd-wallet:
	@echo "=== Importing HD Wallet ==="
	@if [ ! -d "$(HD_WALLET_DIR)" ]; then \
		echo "ERROR: HD wallet directory not found: $(HD_WALLET_DIR)"; \
		echo "Run: make generate-hd-wallet"; \
		exit 1; \
	fi
	@if [ -f "wallets.json" ]; then \
		BACKUP="wallets-backup-$$(date +%Y%m%d-%H%M%S).json"; \
		echo "Backing up existing wallets.json to $$BACKUP"; \
		mv wallets.json $$BACKUP; \
	fi
	@echo ""
	@if [ -d "$(LOCAL_VENV)" ] && [ -f "$(LOCAL_VENV)/bin/python3" ]; then \
		$(LOCAL_VENV)/bin/python3 ./import-hd-wallets.py $(HD_WALLET_DIR) $(LOCAL_WALLETS); \
	else \
		python3 ./import-hd-wallets.py $(HD_WALLET_DIR) $(LOCAL_WALLETS); \
	fi
	@echo ""
	@echo "✓ HD wallet imported and signed successfully!"
	@echo ""
	@echo "Next step: make start-local"

# Complete setup: init + generate + import
setup-local:
	@echo "=== Complete Local Mining Setup ==="
	@echo ""
	@$(MAKE) init-local
	@echo ""
	@if [ ! -f "wallets.json" ]; then \
		if [ ! -d "$(HD_WALLET_DIR)" ]; then \
			$(MAKE) generate-hd-wallet; \
			echo ""; \
		fi; \
		$(MAKE) import-hd-wallet; \
	fi
	@echo ""
	@echo "=== Setup Complete! ==="
	@echo ""
	@echo "⚠️  BACKUP YOUR MNEMONIC:"
	@echo "  cp $(HD_WALLET_DIR)/mnemonic.txt ~/BACKUP/"
	@echo ""
	@echo "Start mining: make start-local"

# Live monitoring with filtered output
watch-local:
	@echo "=== Live Mining Monitor (Ctrl+C to exit) ==="
	@echo ""
	@if [ ! -f "$(LOCAL_PID_FILE)" ] || ! kill -0 $$(cat $(LOCAL_PID_FILE)) 2>/dev/null; then \
		echo "⚠️  Miner is not running"; \
		echo "Start with: make start-local"; \
		exit 1; \
	fi
	@echo "Filtering for: Hash Rate, Solutions, Workers, Challenges"
	@echo "Full logs: make logs-local"
	@echo ""
	@tail -f $(LOCAL_LOG_FILE) | grep --line-buffered -E "^(INFO:|ERROR:|WARNING:|[0-9]{4}-[0-9]{2}-[0-9]{2})"

# Show only important events
events-local:
	@echo "=== Recent Mining Events ==="
	@echo ""
	@if [ ! -f "$(LOCAL_LOG_FILE)" ]; then \
		echo "No log file found"; \
		exit 1; \
	fi
	@echo "Solutions found:"
	@grep "^INFO:" $(LOCAL_LOG_FILE) | grep -i "solution" | tail -5 || echo "  None yet"
	@echo ""
	@echo "Challenges discovered:"
	@grep "^INFO:" $(LOCAL_LOG_FILE) | grep -i "challenge" | tail -5 || echo "  None yet"
	@echo ""
	@echo "Workers active:"
	@grep "^INFO:" $(LOCAL_LOG_FILE) | grep "All.*workers started" | tail -1 || echo "  Starting up..."
	@echo ""
	@echo "For live updates: make watch-local"

# Monitor with auto-refresh (requires watch command)
monitor-local:
	@if ! command -v watch >/dev/null 2>&1; then \
		echo "ERROR: 'watch' command not found"; \
		echo "Install with: sudo apt install procps"; \
		echo ""; \
		echo "Alternative: make watch-local"; \
		exit 1; \
	fi
	@watch -n 2 "$(MAKE) -s monitor-status 2>/dev/null"

# Internal target for monitor display - shows compact summary
monitor-status:
	@if [ ! -f "$(LOCAL_LOG_FILE)" ]; then \
		echo "No log file found. Start miner with: make start-local"; \
		exit 1; \
	fi
	@echo "=== MIDNIGHT MINER - Compact View ==="
	@echo ""
	@# Extract latest stats in consistent order
	@STATS_BLOCK=$$(tail -50 $(LOCAL_LOG_FILE) | \
		sed 's/\x1b\[[0-9;]*[mGKHJD]//g' | \
		sed 's/\[H\[2J\[3J//g'); \
	echo "$$STATS_BLOCK" | grep "^Active Workers:" | tail -1; \
	echo "$$STATS_BLOCK" | grep "^Total Hash Rate:" | tail -1; \
	echo "$$STATS_BLOCK" | grep "^Total Completed:" | tail -1; \
	echo "$$STATS_BLOCK" | grep "^Total NIGHT" | tail -1
	@echo ""
	@# Get worker count from "Active Workers" line and show sample workers
	@WORKER_COUNT=$$(tail -50 $(LOCAL_LOG_FILE) | \
		sed 's/\x1b\[[0-9;]*[mGKHJD]//g' | \
		grep "^Active Workers:" | \
		tail -1 | \
		awk '{print $$3}'); \
	RECENT_WORKERS=$$(tail -100 $(LOCAL_LOG_FILE) | \
		sed 's/\x1b\[[0-9;]*[mGKHJD]//g' | \
		sed 's/\[H\[2J\[3J//g' | \
		grep -E "^[0-9]+\s+(addr|developer)" | \
		tail -25); \
	if [ ! -z "$$WORKER_COUNT" ] && [ $$WORKER_COUNT -gt 6 ]; then \
		echo "Workers (first 3 + last 3 of $$WORKER_COUNT):"; \
		echo "$$RECENT_WORKERS" | head -3; \
		echo "   ... ($$(($$WORKER_COUNT - 6)) workers hidden) ..."; \
		echo "$$RECENT_WORKERS" | tail -3; \
	elif [ ! -z "$$WORKER_COUNT" ] && [ $$WORKER_COUNT -gt 0 ]; then \
		echo "Workers ($$WORKER_COUNT total):"; \
		echo "$$RECENT_WORKERS" | head -$$WORKER_COUNT; \
	else \
		echo "Workers: No data yet..."; \
	fi
	@echo ""
	@echo "Full view: make watch-local | Full table: tail -f miner.log"

# Show wallet addresses
wallets-local:
	@echo "=== Local Wallet Addresses ==="
	@echo ""
	@if [ ! -f "wallets.json" ]; then \
		echo "No wallets found"; \
		exit 1; \
	fi
	@echo "Total wallets: $$(jq 'length' wallets.json)"
	@echo ""
	@echo "Addresses:"
	@jq -r 'to_entries | .[] | "\(.key + 1). \(.value.address)"' wallets.json
	@echo ""
	@if [ -f "$(HD_WALLET_DIR)/mnemonic.txt" ]; then \
		echo "Master mnemonic: $(HD_WALLET_DIR)/mnemonic.txt"; \
	fi

# Verify HD wallet addresses match
verify-local:
	@if [ -d "$(LOCAL_VENV)" ] && [ -f "$(LOCAL_VENV)/bin/python3" ]; then \
		$(LOCAL_VENV)/bin/python3 verify-hd-wallets.py; \
	else \
		python3 verify-hd-wallets.py; \
	fi
