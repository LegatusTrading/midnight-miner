# MidnightMiner Documentation

Welcome to the MidnightMiner documentation. This directory contains comprehensive guides and technical documentation for understanding and deploying the MidnightMiner solution.

---

## Table of Contents

1. **[Journey](./JOURNEY.md)** - The complete story of how we arrived at the final solution
2. **[Architecture](./ARCHITECTURE.md)** - Technical deep-dive into system design and implementation
3. **[Deployment Guide](../README.md)** - Step-by-step deployment instructions (in root)

---

## Quick Links

### For New Users

Start here to understand the project:

1. Read **[JOURNEY.md](./JOURNEY.md)** to understand:
   - What problem we were solving
   - What solutions we tried
   - Why MidnightMiner was chosen
   - How we achieved BIP39 mnemonic support

2. Review **[ARCHITECTURE.md](./ARCHITECTURE.md)** to learn:
   - How the system works
   - Core components and their responsibilities
   - Data flow and mining cycle
   - Performance characteristics

3. Follow the **[Deployment Guide](../README.md)** to:
   - Set up your own mining VPS
   - Generate wallets with mnemonics
   - Start mining NIGHT tokens

### For Developers

Contributing to the project? Read these in order:

1. **[ARCHITECTURE.md](./ARCHITECTURE.md)** - System design
2. **Code Structure** - See `/src` directory
3. **Testing** - Run `pytest tests/`
4. **Contributing** - Open issues/PRs on GitHub

---

## Document Overview

### JOURNEY.md

**Purpose:** Historical context and decision-making process

**Key Topics:**
- Initial research phase
- Five solution attempts (VPS1-VPS5)
- Why night-miner failed on VPS3
- How we added BIP39 support
- Performance analysis
- Lessons learned

**Target Audience:** Anyone wanting to understand the project's history

**Read Time:** ~20 minutes

---

### ARCHITECTURE.md

**Purpose:** Technical implementation details

**Key Topics:**
- System architecture diagram
- Core component responsibilities
- BIP39 mnemonic implementation
- Data flow and mining cycle
- Performance characteristics
- Security considerations

**Target Audience:** Developers and technical users

**Read Time:** ~30 minutes

---

## Project Stats

**Current Status (2025-11-14):**
- **Active VPS:** 2 (VPS4, VPS5)
- **Total Wallets:** 22 (all with BIP39 mnemonics)
- **Solutions Found:** 160
- **NIGHT Earned:** 160.93 NIGHT
- **Combined Hash Rate:** ~16.7 KH/s
- **Cost per NIGHT:** ~€0.054

---

## Key Achievements

### 1. VPS Compatibility ✅

Unlike closed-source miners (night-miner), MidnightMiner works reliably on VPS infrastructure without anti-bot detection.

### 2. BIP39 Mnemonic Support ✅

First mining solution to support standard Cardano BIP39 mnemonics, enabling:
- Wallet import to NuFi, Eternl, Daedalus
- Hardware wallet integration
- Standard backup procedures (15-word phrases)

### 3. Production-Ready ✅

- Stable 24/7 operation
- ~8 KH/s per 8-core VPS
- Smart challenge selection
- Automated wallet rotation

### 4. Open Source ✅

- Full source code available
- Community auditable
- Customizable for specific needs

---

## Getting Started

### Prerequisites

- Ubuntu 24.04 VPS (8 cores, 32GB RAM recommended)
- Python 3.12+
- 8GB disk space
- Internet connection

### Quick Start

```bash
# 1. Clone repository
git clone https://github.com/LegatusTrading/midnight-miner.git
cd midnight-miner

# 2. Install dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 3. Generate wallets (12 wallets with BIP39 mnemonics)
python miner.py --generate-wallets 12

# 4. Backup wallets.json (CRITICAL!)
cp wallets.json ~/backups/wallets-$(date +%Y%m%d).json

# 5. Start mining
python miner.py --workers 8
```

**Expected Results:**
- Hash Rate: ~8 KH/s
- Solutions: ~96 per day
- NIGHT Earned: ~96 NIGHT per day

---

## Documentation Structure

```
docs/
├── README.md          # This file - Documentation index
├── JOURNEY.md         # Historical context and decision process
└── ARCHITECTURE.md    # Technical implementation details

../
├── README.md          # Quick start and deployment guide
├── miner.py          # Main mining script
├── requirements.txt   # Python dependencies
├── wallets.json      # Generated wallets (keep private!)
└── libs/             # Native AshMaize libraries
    └── linux-x64/
        └── ashmaize_py.so
```

---

## Important Notes

### Security Warning

**wallets.json contains sensitive information:**
- Private keys for all wallets
- BIP39 mnemonic recovery phrases
- Anyone with access to this file controls the wallets

**Best Practices:**
1. Set file permissions: `chmod 600 wallets.json`
2. Backup to encrypted storage
3. Write mnemonics on paper/metal for offline backup
4. Never commit wallets.json to version control
5. Never share mnemonics with anyone

### Backup Strategy

**Critical Files:**
- `wallets.json` - Contains all wallet credentials
- `challenges.json` - Mining state (can be regenerated)
- `balances.json` - Balance history (for monitoring)

**Recommended Schedule:**
- Hourly: Copy wallets.json to encrypted location
- Daily: Export mnemonics to secure password manager
- Weekly: Full VPS backup
- Monthly: Verify mnemonic recovery in test wallet

---

## Performance Expectations

### Single VPS (8 cores)

**Hardware:** AMD EPYC 7543, 8 vCPUs, 32GB RAM

**Performance:**
- Hash Rate: ~8.4 KH/s
- Solutions: ~96 per day
- NIGHT Earned: ~96 NIGHT per day
- Cost: €5.23/day
- Profit: ~91 NIGHT/day (at current prices)

### Multiple VPS (Scalable)

**2 VPS (Current Setup):**
- Combined Hash Rate: ~16.7 KH/s
- Solutions: ~192 per day
- NIGHT Earned: ~192 NIGHT per day
- Cost: €10.46/day
- Profit: ~182 NIGHT/day

**Scaling Formula:**
- Hash Rate per VPS: ~8.3 KH/s
- Cost per VPS: €5.23/day
- ROI per VPS: ~€13/day (at 1 NIGHT = €0.15)

---

## Troubleshooting

### Common Issues

**1. Low Hash Rate**
- Check CPU usage: `top`
- Verify all workers running
- Ensure no thermal throttling

**2. No Solutions**
- Check internet connection
- Verify API accessibility: `curl https://sm.midnight.gd/api/challenges`
- Review logs for errors

**3. Wallet Import Fails**
- Verify 15-word mnemonic format
- Check derivation path: m/1852'/1815'/0'/0/0
- Try different wallet (NuFi vs Eternl)

### Getting Help

- **GitHub Issues:** https://github.com/LegatusTrading/midnight-miner/issues
- **Documentation:** https://github.com/LegatusTrading/midnight-miner/tree/main/docs
- **Community:** Discord/Telegram (links in main README)

---

## Version History

**v1.0.0 (2025-11-14)**
- Initial release with BIP39 support
- VPS4 and VPS5 deployments successful
- Comprehensive documentation
- 160 NIGHT earned in first 24 hours

---

## Contributing

We welcome contributions! Please:

1. Read the documentation
2. Check existing issues
3. Open a PR with clear description
4. Follow coding standards
5. Add tests for new features

---

## License

See [LICENSE](../LICENSE) file for details.

---

## Acknowledgments

- **Original MidnightMiner:** Community-developed Python miner
- **AshMaize Algorithm:** Circadian Risk team
- **Midnight Network:** For the innovative blockchain platform
- **Community:** For testing and feedback

---

**Repository:** https://github.com/LegatusTrading/midnight-miner
**Documentation:** https://github.com/LegatusTrading/midnight-miner/tree/main/docs
**Issues:** https://github.com/LegatusTrading/midnight-miner/issues

*Last Updated: 2025-11-14*
