#!/usr/bin/env python3
"""
Fetch wallet statistics from sm.midnight.gd API
Run this locally from your machine (not on VPS) to avoid Vercel checkpoint
"""

import json
import sys
import urllib.request
import urllib.error
from pathlib import Path


def fetch_stats(address):
    """Fetch statistics for a single wallet address"""
    url = f"https://sm.midnight.gd/api/statistics/{address}"
    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Accept': 'application/json',
    }

    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            local_data = data.get('local', {})
            return {
                'crypto_receipts': local_data.get('crypto_receipts', 0),
                'night_allocation': local_data.get('night_allocation', 0)
            }
    except Exception as e:
        print(f"  Error fetching {address[:20]}...: {e}", file=sys.stderr)
        return None


def main():
    if len(sys.argv) < 2:
        print("Usage: ./fetch-wallet-stats.py <wallets.json>")
        print("")
        print("Example:")
        print("  ./fetch-wallet-stats.py data/s1/wallets.json")
        print("  ./fetch-wallet-stats.py data/s1/wallets-20251116-003950.json")
        sys.exit(1)

    wallets_file = Path(sys.argv[1])

    if not wallets_file.exists():
        print(f"Error: File not found: {wallets_file}")
        sys.exit(1)

    # Load wallets
    with open(wallets_file) as f:
        wallets = json.load(f)

    # Filter HD wallets (base addresses)
    hd_wallets = [w for w in wallets if w['address'].startswith('addr1q')]

    print(f"\nFetching stats for {len(hd_wallets)} wallets...\n")
    print(f"{'#':<4} {'Crypto':<10} {'Night':<12} {'Address'}")
    print("-" * 110)

    total_crypto = 0
    total_night = 0.0

    for i, wallet in enumerate(hd_wallets):
        addr = wallet['address']
        stats = fetch_stats(addr)

        if stats:
            crypto = stats['crypto_receipts']
            night = stats['night_allocation']
            total_crypto += crypto
            total_night += night

            print(f"{i:<4} {crypto:<10} {night:<12.2f} {addr}")
        else:
            print(f"{i:<4} {'ERR':<10} {'ERR':<12} {addr}")

    print("-" * 110)
    print(f"{'TOTAL':<4} {total_crypto:<10} {total_night:<12.2f}")
    print("")
    print(f"Total Crypto Receipts: {total_crypto}")
    print(f"Total NIGHT Allocation: {total_night:.2f}")


if __name__ == "__main__":
    main()
