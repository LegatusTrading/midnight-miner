# Midnight Miner

Automated deployment and management system for NIGHT token mining on Linux VPS servers.

## Overview

Midnight Miner is a complete mining solution that combines:
- **Python orchestrator** for multi-wallet management
- **Rust native libraries** for high-performance AshMaize PoW algorithm
- **Automated deployment** via Makefile commands
- **Systemd integration** for 24/7 mining

## Features

- **HD Wallet Support** - Single recovery phrase controls all wallets (CIP-1852 standard)
- **Local & VPS Execution** - Run on your machine or deploy to cloud servers
- Automated VPS initialization with user setup and SSH keys
- One-command deployment and updates
- Multi-wallet mining with proper key derivation
- Real-time status monitoring and backup
- Systemd service for automatic restarts
- Clean separation of code and sensitive data

## Installation

### Prerequisites

Before running the miner, ensure you have the required dependencies:

```bash
# Install jq (JSON processor)
sudo apt install jq  # Ubuntu/Debian
# or
brew install jq      # macOS

# Install Python dependencies
pip install -r requirements.txt
```

### Cardano Tools (for HD Wallet generation)

The project includes `cardano-address` binary. If you need `cardano-cli`:

```bash
# Download cardano-cli binary
mkdir -p ~/.local/bin
# Visit https://github.com/IntersectMBO/cardano-node/releases
# Download latest cardano-cli for your platform
# Extract and place in ~/.local/bin/cardano-cli
chmod +x ~/.local/bin/cardano-cli
```

## Quick Start

### Local Mining (No VPS Required)

**Simplified Setup** - Everything in one command:

```bash
# Complete setup (environment + HD wallet + import)
make setup-local

# BACKUP THE MNEMONIC! (This controls all wallets)
cp hd-wallets/mnemonic.txt ~/BACKUP/

# Start mining
make start-local

# Monitor live (filtered output - recommended!)
make watch-local
```

**Manual Setup** - Step by step:

```bash
# 1. Generate HD wallet
# NOTE: Can be configured to derive desired number of derivations
make generate-hd-wallet

# 2. BACKUP THE MNEMONIC!
cp hd-wallets/mnemonic.txt ~/BACKUP/

# 3. Import to miner format
make import-hd-wallet

# 4. Setup environment
make init-local

# 5. Start mining
make start-local

# 6. Monitor
make watch-local
```

**Monitoring Commands:**

```bash
make watch-local    # Live filtered logs (recommended!)
make status-local   # Quick status snapshot
make events-local   # Recent events summary
make wallets-local  # List wallet addresses
```

**Troubleshooting:**

If you have old wallets that aren't registered (from a previous version):

```bash
# Use the registration tool to register existing wallets
.venv/bin/python3 register-wallets.py
```

Note: `make import-hd-wallet` automatically registers wallets with the API.

### VPS Mining (24/7 Cloud Mining)

Deploy to a remote VPS server:

```bash
# 1. Configure VPS
cp config/v01.conf.example config/v01.conf
# Edit config/v01.conf with your VPS details

# 2. Install mining software
make init-v01

# 3. Start mining
make start-v01

# 4. Check status
make status-v01

# 5. Backup wallets (important!)
make backup-v01
```

## Architecture

### Mining Strategy

This miner implements an **optimized challenge selection strategy**:

1. **Multi-Wallet Approach**: Creates 16 wallets for 8 workers (2:1 ratio)
   - Workers select from available wallets with unsolved challenges
   - Reduces wallet contention and improves challenge selection
   - Distributes solutions across multiple addresses
2. **Challenge Accumulation**: Discovers and stores challenges over time
3. **Smart Selection**: Always mines the easiest available challenge with sufficient deadline buffer
4. **Deadline Safety**: 2-hour buffer ensures solutions are submitted before expiry
5. **Dynamic Expansion**: Automatically creates more wallets if all 16 are busy

### Components

- `miner.py` - Python orchestrator managing workers and API communication
- `libs/linux-x64/ashmaize_py.so` - Native Rust library for PoW computation
- `scripts/` - Helper scripts for deployment and status monitoring
- `Makefile` - Automation for all operations

## Requirements

### Local Machine
- Unix-like OS (Linux/macOS)
- Python 3.8+ with pip
- `make`, `ssh`, `rsync` installed
- **For HD Wallet Generation:**
  - `cardano-address` (included in project root)
  - `cardano-cli` (installed at `~/.local/bin/cardano-cli`)
  - `jq` (JSON processor)

### VPS Server
- Ubuntu 24.04 LTS (recommended)
- 8+ CPU cores (for optimal hash rate)
- 4GB+ RAM
- **SSH key access to root** (must be already configured)

## Commands Reference

### Setup

```bash
make init-<host>     # Install mining software on VPS
```

### Mining Control

```bash
make start-<host>    # Start mining
make stop-<host>     # Stop mining
make status-<host>   # Show status and save report
make backup-<host>   # Backup wallets and data
```

## Configuration

Config files are in `config/<host>.conf`:

```bash
HOSTNAME=123.234.33.53        # VPS IP address
DATA_DIR=./data/v01           # Local backup directory
```

**Notes:**
- SSH key access to root must be configured before using these tools
- Miner runs as root in `/root/midnight-miner` for simplified deployment
- All `config/*.conf` files (except `.example`) are gitignored for security

## Performance

**Expected hash rate (8-core VPS):** ~8-9 KH/s

**Solution rate:** Variable, depends on:
- Challenge difficulty
- Number of active challenges
- Hash rate consistency

**Wallet format:** BIP39 15-word mnemonic (compatible with NuFi/Eternl wallets)

## Security

- All sensitive files are gitignored (configs, wallets, data)
- SSH key-based authentication only
- Wallets use standard BIP39 mnemonics for recovery
- No private keys or credentials in repository

**Always backup your wallets immediately after generation!**

## File Structure

```
midnight-miner/
├── config/              # VPS configurations (gitignored)
│   └── v01.conf.example # Example config
├── data/                # Local backups (gitignored)
├── scripts/             # Deployment helper scripts
│   ├── init-user.sh     # VPS user initialization
│   ├── install-service.sh # Systemd service setup
│   └── get-status.sh    # Status report generator
├── libs/                # Native Rust libraries
│   └── linux-x64/
│       └── ashmaize_py.so # AshMaize PoW implementation
├── miner.py             # Main Python orchestrator
├── requirements.txt     # Python dependencies
├── Makefile             # Automation commands
├── README.md            # This file
└── QUICKSTART.md        # Quick start guide
```

## Multiple VPS Management

Manage multiple mining servers by creating separate config files:

```bash
config/v01.conf  # First VPS
config/v02.conf  # Second VPS
config/v03.conf  # Third VPS
```

Then run commands with different host names:

```bash
make status-v01
make status-v02
make backup-v03
```

## Troubleshooting

**SSH Connection Issues:**
```bash
ssh root@vps.ip.address
```
Ensure SSH key access to root is configured in your VPS provider's console.

**Mining Not Starting:**
```bash
ssh root@vps "journalctl -u midnight-miner -n 100"
```

**Check Systemd Status:**
```bash
ssh root@vps "systemctl status midnight-miner"
```

## License

Apache-2.0 OR MIT

## Disclaimer

This software is provided as-is without warranty. Use at your own risk. Always backup your wallet files and mnemonic phrases securely.

---

**For detailed setup instructions, see [QUICKSTART.md](QUICKSTART.md)**
