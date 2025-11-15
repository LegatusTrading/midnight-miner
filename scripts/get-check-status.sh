#!/bin/bash
# Get check status with mnemonic and wallet statistics
# Run this script on the VPS as root

set -e

MINER_DIR="/root/midnight-miner"
WALLETS_FILE="$MINER_DIR/wallets.json"
MNEMONIC_FILE="$MINER_DIR/hd-wallets/mnemonic.txt"
VPS_IP="${1:-$(hostname -I | awk '{print $1}')}"

echo ""
echo "=== Check: $(hostname -s) ==="
echo ""
echo "- Time: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo "- Host: $(hostname)"
echo "- IP  : $VPS_IP"
echo ""

# Display mnemonic (first 4 words)
echo "== Wallet: 1"
echo ""
if [ -f "$MNEMONIC_FILE" ]; then
    MNEMONIC=$(cat "$MNEMONIC_FILE")
    FIRST_FOUR=$(echo "$MNEMONIC" | awk '{print $1, $2, $3, $4}')
    echo "- Seed: $FIRST_FOUR .."
else
    echo "- Seed: ⚠️  Mnemonic not found!"
fi
echo ""

# Display wallets with solution counts and API data
if [ -f "$WALLETS_FILE" ]; then
    python3 << 'PYEOF'
import json
import subprocess
import sys
import urllib.request
import urllib.error

# Load wallets
try:
    with open('/root/midnight-miner/wallets.json') as f:
        wallets = json.load(f)
except Exception as e:
    print(f"Error loading wallets: {e}")
    sys.exit(1)

# Get all solution logs once
try:
    result = subprocess.run(
        ['journalctl', '-u', 'midnight-miner', '--no-pager'],
        capture_output=True, text=True, timeout=10
    )
    solution_lines = [line for line in result.stdout.split('\n') if 'Solution accepted' in line]
except Exception as e:
    solution_lines = []

# Filter out developer donation wallet (enterprise address)
hd_wallets = [w for w in wallets if w['address'].startswith('addr1q')]

print(f"== Addresses: {len(hd_wallets)}")
print("")
print(f"{'#':<4} {'Sols':<6} {'Crypto':<8} {'Night':<8} {'Address'}")
print("-" * 110)

for i, wallet in enumerate(hd_wallets):
    addr = wallet['address']
    addr_prefix = addr[:39]

    # Count solutions for this address
    solution_count = sum(1 for line in solution_lines if addr_prefix in line)

    # Note: Crypto/Night columns require running locally due to Vercel bot detection
    # Use: ./scripts/fetch-wallet-stats.py data/<host>/wallets.json
    crypto_receipts = "-"
    night_allocation = "-"

    print(f"{i:<4} {solution_count:<6} {crypto_receipts:<8} {night_allocation:<8} {addr}")

print("-" * 110)
PYEOF
else
    echo "⚠️  No wallets file found"
fi

echo ""
echo "== Mining"
echo ""

# Service status
if systemctl is-active --quiet midnight-miner; then
    echo "- Status: Running ✅"

    # Get latest stats from logs
    LAST_HASHRATE=$(journalctl -u midnight-miner -n 100 --no-pager | grep "Total Hash Rate" | tail -1 | awk '{print $(NF-1), $NF}')
    TOTAL_COMPLETED=$(journalctl -u midnight-miner -n 100 --no-pager | grep "Total Completed" | tail -1 | awk '{print $NF}')

    if [ -n "$LAST_HASHRATE" ]; then
        echo "- Hash Rate: $LAST_HASHRATE"
    fi

    if [ -n "$TOTAL_COMPLETED" ]; then
        echo "- Solutions: $TOTAL_COMPLETED"
    fi
else
    echo "- Status: Stopped ❌"
fi

echo ""
