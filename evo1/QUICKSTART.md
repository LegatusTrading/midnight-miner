# Midnight Miner - Quick Start Guide

Deploy and manage NIGHT token mining on Linux VPS servers with simple commands.

## Prerequisites

- Linux VPS with Ubuntu 24.04 (8+ CPU cores recommended)
- **SSH key access to root** (must be already configured)
- Local machine with `make`, `ssh`, and `rsync` installed

## Quick Setup (3 minutes)

### 1. Configure Your VPS

Create a config file from the example:

```bash
cp config/v01.conf.example config/v01.conf
```

Edit `config/v01.conf` with your VPS details:

```bash
HOSTNAME=your.vps.ip.address
DATA_DIR=./data/v01
```

### 2. Install Mining Software

This will install dependencies and set up the miner:

```bash
make init-v01
```

This will:
- Install Python, dependencies, and build tools
- Upload the miner code to `/root/midnight-miner`
- Set up systemd service for auto-start (runs as root)

### 3. Start Mining

```bash
make start-v01
```

Mining will start automatically and generate 16 wallets with BIP39 recovery phrases.
8 workers will mine simultaneously, selecting from the 16 available wallets.

## Daily Operations

### Check Mining Status

```bash
make status-v01
```

Shows:
- Hash rate
- Total solutions found
- Solutions per wallet
- System resources

### Backup Wallets and Data

```bash
make backup-v01
```

Downloads wallets, balances, and challenges to `./data/v01/` (gitignored).

**IMPORTANT:** Backup wallets immediately after first run!

### Stop Mining

```bash
make stop-v01
```

### View Live Logs (on VPS)

```bash
ssh root@vps.ip.address
journalctl -u midnight-miner -f
```

## Expected Performance

- **Hash Rate:** ~8-9 KH/s (8-core VPS)
- **Solutions:** Variable, depends on challenge difficulty
- **Wallet Format:** BIP39 15-word mnemonic (compatible with NuFi/Eternl)

## File Structure

```
midnight-miner/
├── config/           # VPS configurations (gitignored)
├── data/             # Backups and status reports (gitignored)
├── scripts/          # Helper scripts
├── miner.py          # Python orchestrator
├── libs/             # Rust native libraries
├── requirements.txt  # Python dependencies
└── Makefile          # Deployment automation
```

## Security Notes

- Config files (`config/*.conf`) are gitignored
- Data directories (`data/`, `vps/`) are gitignored
- Wallet files are never committed to git
- Always backup `wallets.json` immediately after generation

## Troubleshooting

### SSH Connection Issues

Verify you can connect as root:

```bash
ssh root@vps.ip.address
```

If not, check your SSH keys are configured in your VPS provider's console.

### Mining Not Starting

Check service logs:

```bash
ssh root@vps "journalctl -u midnight-miner -n 100"
```

### Check Service Status

```bash
ssh root@vps "systemctl status midnight-miner"
```

## Multiple VPS Management

To manage multiple VPS instances:

1. Create separate config files: `config/v01.conf`, `config/v02.conf`, etc.
2. Run commands with different host names:

```bash
make start-v01
make start-v02
make status-v01
make status-v02
```

## Next Steps

- Review `ARCHITECTURE.md` for technical details
- Check `MINING_GUIDE.md` for optimization tips
- Monitor your wallets for NIGHT token rewards

## Support

For issues or questions, refer to the documentation or open an issue on GitHub.

---

**Happy Mining!** 🌙
