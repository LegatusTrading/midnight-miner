# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MidnightMiner is a Python-based cryptocurrency miner for the Midnight blockchain's Scavenger Mine program. It uses the AshMaize Proof-of-Work algorithm via a native Rust library, achieves ~8 KH/s per 8-core VPS, and supports BIP39 HD wallet generation for full wallet portability.

## Essential Commands

### Local Development & Testing

```bash
# Complete setup (environment + HD wallet + import)
make setup-local

# Start/stop local mining
make start-local
make stop-local
make restart-local

# Monitor mining activity
make watch-local    # Live filtered logs (recommended)
make status-local   # Quick status snapshot
make events-local   # Recent events summary
make logs-local     # Full raw logs
```

### VPS Deployment

```bash
# Initialize VPS with mining software
make init-v01

# Control mining on VPS
make start-v01
make stop-v01
make status-v01
make backup-v01

# Replace 'v01' with any config name from config/*.conf
```

### HD Wallet Management

```bash
# Generate new HD wallet with BIP39 mnemonic
make generate-hd-wallet

# Import HD wallet to miner format and register with API
make import-hd-wallet

# Verify HD wallet addresses match
make verify-local

# Show wallet addresses
make wallets-local
```

## Architecture

### Core Components

1. **miner.py** - Main orchestrator
   - Multi-worker challenge solving (default: 8 workers)
   - Multi-wallet rotation (default: 16 wallets, 2:1 ratio)
   - API communication for challenges and solutions
   - Smart challenge selection (easiest first, 2-hour deadline buffer)
   - Automatic wallet expansion when all wallets are busy

2. **Native Library** (`libs/*/ashmaize_py.so`)
   - Rust-based AshMaize PoW implementation
   - Platform-specific binaries (Linux/macOS, x64/ARM)
   - Loaded via `ashmaize_loader.py` with automatic platform detection
   - High-performance VM execution and ROM generation

3. **HD Wallet System**
   - `generate-hd-wallet.sh` - Bash script using `cardano-address` and `cardano-cli`
   - `import-hd-wallets.py` - Converts HD wallet format to miner format
   - `verify-hd-wallets.py` - Validates address derivation
   - BIP39 mnemonic generation (15-24 words)
   - CIP-1852 derivation path: `m/1852'/1815'/account'/0/0`

4. **Deployment Scripts** (`scripts/`)
   - `install-service.sh` - Sets up systemd service for 24/7 mining
   - `get-status.sh` - Generates status reports
   - `get-local-status.sh` - Local status reporting

### Data Files (gitignored)

- `wallets.json` - Wallet addresses and private keys in miner format
- `balances.json` - NIGHT token balance snapshots
- `challenges.json` - Challenge history and state
- `hd-wallets/` - HD wallet derivation data (mnemonic, keys, addresses)
- `config/*.conf` - VPS configuration files (except `.example`)

### Mining Strategy

The miner uses an **optimized challenge selection strategy**:

1. Creates 16 wallets for 8 workers (2:1 ratio) to reduce wallet contention
2. Fetches all active challenges from API
3. Filters challenges with < 2-hour deadline buffer
4. Sorts by difficulty (easiest first)
5. Workers select from available wallets with unsolved challenges
6. Submits solutions and rotates to next wallet
7. Automatically creates more wallets if all 16 are busy

### API Integration

- Base URL: `https://sm.midnight.gd/api/`
- Endpoints: `/challenges`, `/submit`, `/balance/{address}`
- No authentication required (wallet address serves as identity)
- Rate limiting handled automatically with exponential backoff

## Development Guidelines

### Working with Wallets

- **CRITICAL**: Always backup `hd-wallets/mnemonic.txt` immediately after generation
- Wallets use BIP39 mnemonics compatible with NuFi/Eternl/Daedalus
- Never commit wallets, mnemonics, or private keys to git
- Use `make import-hd-wallet` to ensure wallets are registered with API
- For old wallets not registered: use `register-wallets.py`

### Testing Changes

1. Test locally first: `make start-local` and monitor with `make watch-local`
2. Check for errors in `miner.log`
3. Verify wallet generation: `make verify-local`
4. For VPS deployment: test on one VPS before deploying to all

### Platform Compatibility

- **Python**: 3.8+ required (3.12 recommended)
- **Native library**: Platform-specific `.so` files in `libs/{platform}-{arch}/`
- **Cardano tools**: `cardano-address` and `cardano-cli` auto-downloaded by `make init-local`
- **Dependencies**: Install via `pip install -r requirements.txt`

### Configuration Management

VPS configs are in `config/<host>.conf`:
```bash
HOSTNAME=123.234.33.53    # VPS IP address
DATA_DIR=./data/v01       # Local backup directory
```

All `config/*.conf` files (except `.example`) are gitignored for security.

### Key Files to Understand

- `miner.py:0-150` - Initialization and imports
- `generate-hd-wallet.sh` - HD wallet generation logic
- `import-hd-wallets.py` - HD wallet import and API registration
- `Makefile` - All automation commands
- `docs/ARCHITECTURE.md` - Detailed system architecture

### Security Considerations

- Private keys stored in `wallets.json` with 600 permissions
- BIP39 mnemonics enable recovery without wallets.json
- No API keys required (wallet address serves as identity)
- Solutions verified cryptographically by the API
- All sensitive files are gitignored

## Common Development Tasks

### Adding a New Worker Strategy

1. Modify worker selection logic in `miner.py` (worker thread function)
2. Update challenge selection strategy if needed
3. Test with `make start-local` and monitor hash rate changes
4. Document performance impact in commit message

### Updating Native Library

1. Replace platform-specific `.so` file in `libs/{platform}-{arch}/`
2. Ensure `ashmaize_loader.py` detects the platform correctly
3. Test with `make start-local` to verify library loads
4. Update version in `miner.py` if needed

### Adding New VPS

1. Create new config: `cp config/v01.conf.example config/v02.conf`
2. Edit `config/v02.conf` with VPS IP and data directory
3. Ensure SSH key access to root is configured
4. Run `make init-v02` to setup
5. Run `make start-v02` to begin mining

### Modifying HD Wallet Derivation

1. Edit `generate-hd-wallet.sh` derivation path or account count
2. Update `import-hd-wallets.py` to match derivation logic
3. Test with `make generate-hd-wallet` (backup existing first!)
4. Verify with `make verify-local`

## Notes

- The miner runs as root on VPS for simplified deployment
- Hash rate: ~8-9 KH/s per 8-core VPS
- Solution rate varies based on challenge difficulty
- Systemd service ensures 24/7 operation with auto-restart
- Developer donation rate: 5% (configurable in `miner.py`)
