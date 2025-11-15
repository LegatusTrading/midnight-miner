#!/bin/bash
# Get check status with mnemonic and wallet statistics
# Run this script on the VPS as root

set -e

MINER_DIR="/root/midnight-miner"
WALLETS_FILE="$MINER_DIR/wallets.json"
MNEMONIC_FILE="$MINER_DIR/hd-wallets/mnemonic.txt"

echo "=========================================="
echo "MIDNIGHT MINER - Wallet Check Status"
echo "=========================================="
echo ""
echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo "Hostname: $(hostname)"
echo ""

# Display mnemonic
echo "=========================================="
echo "SEED PHRASE (24 words)"
echo "=========================================="
if [ -f "$MNEMONIC_FILE" ]; then
    cat "$MNEMONIC_FILE"
else
    echo "⚠️  Mnemonic file not found!"
fi
echo ""
echo ""

# Display wallets with solution counts
echo "=========================================="
echo "WALLET ADDRESSES"
echo "=========================================="
echo ""

if [ -f "$WALLETS_FILE" ]; then
    python3 << 'PYEOF'
import json
import subprocess
import sys

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
    print(f"Warning: Could not read journal logs: {e}")
    solution_lines = []

print(f"Total Wallets: {len(wallets)}")
print("")
print(f"{'#':<4} {'Solutions':<10} {'Address':<66} {'Link'}")
print("-" * 140)

for i, wallet in enumerate(wallets):
    addr = wallet['address']
    # Use first 39 chars as address prefix (logs truncate around 40 chars)
    addr_prefix = addr[:39]

    # Count solutions for this address
    solution_count = sum(1 for line in solution_lines if addr_prefix in line)

    # Create verification link
    verify_link = f"https://sm.midnight.gd/api/statistics/{addr}"

    print(f"{i:<4} {solution_count:<10} {addr:<66} {verify_link}")

print("")
PYEOF
else
    echo "⚠️  No wallets file found"
fi

echo ""
echo "=========================================="
echo "MINING STATUS"
echo "=========================================="

# Service status
if systemctl is-active --quiet midnight-miner; then
    echo "Status: Running ✅"

    # Get latest stats from logs
    LAST_HASHRATE=$(journalctl -u midnight-miner -n 100 --no-pager | grep "Total Hash Rate" | tail -1 | awk '{print $(NF-1), $NF}')
    TOTAL_COMPLETED=$(journalctl -u midnight-miner -n 100 --no-pager | grep "Total Completed" | tail -1 | awk '{print $NF}')

    if [ -n "$LAST_HASHRATE" ]; then
        echo "Hash Rate: $LAST_HASHRATE"
    fi

    if [ -n "$TOTAL_COMPLETED" ]; then
        echo "Solutions: $TOTAL_COMPLETED"
    fi
else
    echo "Status: Stopped ❌"
fi

echo ""
echo "=========================================="
echo "⚠️  IMPORTANT: Keep your seed phrase secure!"
echo "   Anyone with the seed can access all wallets."
echo "=========================================="
