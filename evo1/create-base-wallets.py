#!/usr/bin/env python3
"""
Create BASE address wallets from HD mnemonic using PyCardano
Generates wallets.json with BASE addresses (addr1q...) instead of enterprise addresses (addr1v...)
"""
import json
import sys
import hashlib
from datetime import datetime, timezone
from pycardano import HDWallet, Network, Address, PaymentSigningKey, PaymentVerificationKey, StakeVerificationKey
import cbor2

def main():
    if len(sys.argv) < 3:
        print("Usage: create-base-wallets.py <mnemonic_file> <num_accounts>")
        sys.exit(1)

    mnemonic_file = sys.argv[1]
    num_accounts = int(sys.argv[2])

    # Read mnemonic
    with open(mnemonic_file, 'r') as f:
        mnemonic = f.read().strip()

    print(f"Generating {num_accounts} BASE address wallets from mnemonic...")
    print(f"Mnemonic words: {len(mnemonic.split())}")
    print()

    # Create HD wallet from mnemonic
    hdwallet = HDWallet.from_mnemonic(mnemonic)

    wallets = []

    for account in range(num_accounts):
        # CIP-1852 derivation: m/1852'/1815'/account'/0/0 (payment)
        # CIP-1852 derivation: m/1852'/1815'/account'/2/0 (stake)
        payment_hdwallet = hdwallet.derive_from_path(f"m/1852'/1815'/{account}'/0/0")
        stake_hdwallet = hdwallet.derive_from_path(f"m/1852'/1815'/{account}'/2/0")

        # Extract keys (following miner.py pattern)
        payment_xpriv = payment_hdwallet.xprivate_key
        payment_signing_key = PaymentSigningKey.from_primitive(payment_xpriv[:32])
        payment_verification_key = PaymentVerificationKey.from_signing_key(payment_signing_key)

        stake_xpriv = stake_hdwallet.xprivate_key
        stake_signing_key = PaymentSigningKey.from_primitive(stake_xpriv[:32])
        stake_verification_key = StakeVerificationKey.from_signing_key(stake_signing_key)

        # Create BASE address (with stake component)
        address = Address(
            payment_part=payment_verification_key.hash(),
            staking_part=stake_verification_key.hash(),
            network=Network.MAINNET
        )

        # Get hex representation of private key and public key
        payment_skey_hex = bytes(payment_signing_key.to_primitive()).hex()
        payment_vkey_hex = bytes(payment_verification_key.to_primitive()).hex()

        # Generate signature for API registration (COSE Sign1 structure)
        message = "I agree to abide by the terms and conditions as described in version 1-0 of the Midnight scavenger mining process: 281ba5f69f4b943e3fb8a20390878a232787a04e4be22177f2472b63df01c200"
        address_bytes = bytes(address.to_primitive())

        protected = {1: -8, "address": address_bytes}
        protected_encoded = cbor2.dumps(protected)
        unprotected = {"hashed": False}
        payload = message.encode('utf-8')

        sig_structure = ["Signature1", protected_encoded, b'', payload]
        to_sign = cbor2.dumps(sig_structure)
        signature_bytes = payment_signing_key.sign(to_sign)

        cose_sign1 = [protected_encoded, unprotected, payload, signature_bytes]
        signature_hex = cbor2.dumps(cose_sign1).hex()

        wallet_entry = {
            "address": str(address),
            "pubkey": payment_vkey_hex,
            "signing_key": payment_skey_hex,
            "signature": signature_hex,
            "created_at": datetime.now(timezone.utc).isoformat()
        }

        wallets.append(wallet_entry)
        print(f"✓ Account {account:2d}: {str(address)[:50]}...")

    # Write wallets.json
    with open('wallets.json', 'w') as f:
        json.dump(wallets, f, indent=2)

    print()
    print(f"✓ Generated {len(wallets)} wallets")
    print(f"✓ Saved to: wallets.json")
    print()
    print(f"Address type: {wallets[0]['address'][:7]}... (BASE address with stake component)")
    print()

if __name__ == "__main__":
    main()
