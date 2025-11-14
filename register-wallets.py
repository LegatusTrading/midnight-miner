#!/usr/bin/env python3
"""
Register existing wallets with the Midnight mining API
Use this when you have wallets.json with signatures but they weren't registered yet
"""

import json
import sys
import time
import requests
from proxy_config import create_proxy_session

def register_wallet(wallet_data, api_base, session):
    """Register a single wallet with the API"""
    url = f"{api_base}/register/{wallet_data['address']}/{wallet_data['signature']}/{wallet_data['pubkey']}"

    try:
        response = session.post(url, json={}, timeout=15)
        response.raise_for_status()
        return True, "Registered successfully"
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 400:
            error_msg = e.response.json().get('message', '')
            if 'already' in error_msg.lower():
                return True, "Already registered"
        return False, f"HTTP {e.response.status_code}: {e.response.text}"
    except Exception as e:
        return False, str(e)

def main():
    wallets_file = "wallets.json"
    api_base = "https://scavenger.prod.gd.midnighttge.io/"

    if len(sys.argv) > 1:
        wallets_file = sys.argv[1]

    print("="*70)
    print("WALLET REGISTRATION TOOL")
    print("="*70)
    print(f"API: {api_base}")
    print(f"Wallets file: {wallets_file}")
    print()

    # Load wallets
    try:
        with open(wallets_file, 'r') as f:
            wallets = json.load(f)
    except FileNotFoundError:
        print(f"Error: {wallets_file} not found")
        return 1
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in {wallets_file}: {e}")
        return 1

    if not wallets:
        print("No wallets found in file")
        return 1

    print(f"Found {len(wallets)} wallets to register")
    print()

    # Create HTTP session with proxy support
    session, _ = create_proxy_session()

    # Register each wallet
    success_count = 0
    already_registered = 0
    failed = []

    for i, wallet in enumerate(wallets):
        address = wallet['address']
        short_addr = address[:20] + "..." + address[-10:]

        print(f"[{i+1}/{len(wallets)}] {short_addr}...", end=' ', flush=True)

        success, message = register_wallet(wallet, api_base, session)

        if success:
            if "Already" in message:
                print(f"✓ {message}")
                already_registered += 1
            else:
                print(f"✓ {message}")
                success_count += 1
        else:
            print(f"✗ FAILED: {message}")
            failed.append((address, message))

        # Small delay between registrations
        if i < len(wallets) - 1:
            time.sleep(0.5)

    print()
    print("="*70)
    print("REGISTRATION SUMMARY")
    print("="*70)
    print(f"Total wallets:       {len(wallets)}")
    print(f"Newly registered:    {success_count}")
    print(f"Already registered:  {already_registered}")
    print(f"Failed:              {len(failed)}")
    print()

    if failed:
        print("FAILED WALLETS:")
        for addr, error in failed:
            print(f"  {addr[:20]}...{addr[-10:]}")
            print(f"    Error: {error}")
        print()
        print("⚠️  Some wallets failed to register!")
        print("Check your network connection and API availability.")
        return 1
    else:
        print("✓ All wallets registered successfully!")
        print()
        print("You can now start mining:")
        print("  make start-local")
        return 0

if __name__ == "__main__":
    sys.exit(main())
