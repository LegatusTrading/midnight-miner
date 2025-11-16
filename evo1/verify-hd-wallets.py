#!/usr/bin/env python3
"""
Verify that the miner is using HD wallet-derived addresses

Usage:
    .venv/bin/python3 verify-hd-wallets.py
"""

import json
import os
import sys
from pycardano import HDWallet, PaymentSigningKey, PaymentVerificationKey, Address, Network

def derive_address_from_mnemonic(mnemonic, account_num):
    """Derive wallet address from mnemonic (same as import-hd-wallets.py)"""
    hdwallet = HDWallet.from_mnemonic(mnemonic)
    payment_hdwallet = hdwallet.derive_from_path(f"m/1852'/1815'/{account_num}'/0/0")

    # Extract signing key (first 32 bytes of extended private key)
    xpriv = payment_hdwallet.xprivate_key
    signing_key = PaymentSigningKey.from_primitive(xpriv[:32])

    # Generate verification key and address
    verification_key = PaymentVerificationKey.from_signing_key(signing_key)
    address = Address(verification_key.hash(), network=Network.MAINNET)

    return str(address)

def check_miner_running():
    """Check if miner process is running"""
    import subprocess
    try:
        result = subprocess.run(
            ["pgrep", "-f", "python.*miner.py"],
            capture_output=True,
            text=True
        )
        pids = result.stdout.strip().split('\n') if result.stdout.strip() else []
        return len(pids) > 0, pids
    except Exception as e:
        return False, []

def main():
    print("=" * 60)
    print("HD Wallet Verification for Midnight Miner")
    print("=" * 60)
    print()

    # Check if wallets.json exists
    if not os.path.exists("wallets.json"):
        print("❌ wallets.json not found!")
        print("   Run: make import-hd-wallet")
        sys.exit(1)

    # Check if HD wallet directory exists
    hd_wallet_dir = "./hd-wallets"
    if not os.path.exists(hd_wallet_dir):
        print("❌ HD wallet directory not found!")
        print("   Run: make generate-hd-wallet")
        sys.exit(1)

    # Read mnemonic
    mnemonic_file = os.path.join(hd_wallet_dir, "mnemonic.txt")
    if not os.path.exists(mnemonic_file):
        print("❌ Mnemonic file not found!")
        sys.exit(1)

    with open(mnemonic_file, 'r') as f:
        mnemonic = f.read().strip()

    # Read wallets.json
    with open("wallets.json", 'r') as f:
        wallets = json.load(f)

    print(f"📊 Wallets loaded: {len(wallets)}")

    # Count non-developer wallets (addresses starting with "addr1")
    hd_wallets = [w for w in wallets if w.get('address', '').startswith('addr1')]
    dev_wallets = [w for w in wallets if 'developer' in w.get('address', '').lower()]

    print(f"   - HD wallet addresses: {len(hd_wallets)}")
    if dev_wallets:
        print(f"   - Developer wallets: {len(dev_wallets)}")
    print()

    # Check miner status
    running, pids = check_miner_running()
    if running:
        print(f"✅ Miner is RUNNING ({len(pids)} processes)")
    else:
        print("⚠️  Miner is NOT running")
        print("   Start with: make start-local")
    print()

    # Verify addresses match
    print("🔍 Verifying HD wallet derivation...")
    print()

    num_to_check = min(5, len(hd_wallets))
    all_match = True

    for i in range(num_to_check):
        wallet = hd_wallets[i]
        wallet_addr = wallet['address']

        # Derive address from mnemonic
        try:
            derived_addr = derive_address_from_mnemonic(mnemonic, i)
            match = wallet_addr == derived_addr

            if match:
                print(f"✅ Account {i}: {wallet_addr[:20]}... MATCH")
            else:
                print(f"❌ Account {i}: MISMATCH")
                print(f"   wallets.json: {wallet_addr}")
                print(f"   HD derived:   {derived_addr}")
                all_match = False
        except Exception as e:
            print(f"❌ Account {i}: Error deriving address: {e}")
            all_match = False

    if num_to_check < len(hd_wallets):
        print(f"   ... ({len(hd_wallets) - num_to_check} more wallets not shown)")

    print()
    print("=" * 60)

    if all_match:
        print("✅ VERIFICATION PASSED")
        print()
        print("Your miner is using HD wallet-derived addresses!")
        print()
        print("Mnemonic location: hd-wallets/mnemonic.txt")
        print("⚠️  Keep your mnemonic backed up securely!")
        return 0
    else:
        print("❌ VERIFICATION FAILED")
        print()
        print("Your wallets.json does not match HD wallet derivation.")
        print("You may need to re-import:")
        print("  make import-hd-wallet")
        return 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
