#!/bin/bash

#==============================================================================
# Cardano HD Wallet Generator Script
#==============================================================================
# This script generates a hierarchical deterministic (HD) wallet for Cardano
# following the CIP-1852 standard derivation path: m/1852H/1815H/accountH
#
# Features:
#   - Generate new mnemonic or use existing one
#   - Configurable network (mainnet, testnet, preview, preprod)
#   - Configurable mnemonic size (12, 15, 18, 21, or 24 words)
#   - Multiple account generation
#   - Payment and stake address generation
#   - Both enterprise and delegation addresses
#   - Organized output directory
#
# Security Warning:
#   This script generates and stores private keys in plain text files.
#   Only use this for testing or development purposes.
#   For production wallets, use proper key management solutions.
#==============================================================================

set -euo pipefail

#==============================================================================
# Configuration and Defaults
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CARDANO_ADDRESS="${SCRIPT_DIR}/cardano-address"
CARDANO_CLI="${SCRIPT_DIR}/cardano-cli"

# Default settings
DEFAULT_NETWORK="testnet"
DEFAULT_MNEMONIC_SIZE=24
DEFAULT_NUM_ACCOUNTS=50
DEFAULT_NUM_ADDRESSES=3
DEFAULT_OUTPUT_DIR="./wallet-output"

# Current settings (can be overridden by arguments)
NETWORK="$DEFAULT_NETWORK"
MNEMONIC_SIZE="$DEFAULT_MNEMONIC_SIZE"
NUM_ACCOUNTS="$DEFAULT_NUM_ACCOUNTS"
NUM_ADDRESSES="$DEFAULT_NUM_ADDRESSES"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
EXISTING_MNEMONIC=""
QUIET_MODE=false

#==============================================================================
# Help and Usage
#==============================================================================

show_help() {
    cat << 'EOF'
Cardano HD Wallet Generator

USAGE:
    ./generate-hd-wallet.sh [OPTIONS]

DESCRIPTION:
    Generates a Cardano HD wallet with keys and addresses following the
    CIP-1852 derivation standard (m/1852H/1815H/accountH).

OPTIONS:
    -h, --help              Show this help message
    -n, --network NETWORK   Network to use (mainnet, testnet, preview, preprod)
                           Default: testnet
    -s, --size SIZE        Mnemonic size in words (12, 15, 18, 21, 24)
                           Default: 24
    -a, --accounts NUM     Number of accounts to generate (0-100)
                           Default: 50
    -d, --addresses NUM    Number of payment addresses per account (1-20)
                           Default: 3
    -o, --output DIR       Output directory for generated files
                           Default: ./wallet-output
    -m, --mnemonic FILE    Use existing mnemonic from file
    -q, --quiet            Quiet mode (minimal output)

EXAMPLES:
    # Generate testnet wallet with defaults
    ./generate-hd-wallet.sh

    # Generate mainnet wallet with 3 accounts
    ./generate-hd-wallet.sh --network mainnet --accounts 3

    # Generate wallet with custom mnemonic
    ./generate-hd-wallet.sh --mnemonic my-mnemonic.txt

    # Generate preview network wallet with 12-word mnemonic
    ./generate-hd-wallet.sh --network preview --size 12

DERIVATION PATHS:
    Root Key:           Generated from mnemonic seed
    Account Key:        m/1852H/1815H/{account}H
    Payment Address:    m/1852H/1815H/{account}H/0/{index}
    Change Address:     m/1852H/1815H/{account}H/1/{index}
    Stake Address:      m/1852H/1815H/{account}H/2/0

    Where:
      - 1852H = CIP-1852 purpose (Shelley era)
      - 1815H = Cardano coin type
      - H     = Hardened derivation

ADDRESS TYPES:
    Enterprise:  Payment-only address (no staking capability)
                Format: addr1... (mainnet) or addr_test1... (testnet)

    Delegation:  Payment address linked to stake address
                Allows receiving payments and delegating stake

    Stake:       Staking rewards address
                Format: stake1... (mainnet) or stake_test1... (testnet)

OUTPUT STRUCTURE:
    wallet-output/
    ├── mnemonic.txt              # Recovery phrase (24 words)
    ├── root.prv                  # Root private key
    ├── summary.txt               # Human-readable summary
    └── account-{N}/
        ├── account.prv           # Account private key
        ├── account.pub           # Account public key (bech32)
        ├── account.pub.hex       # Account public key (64-char hex)
        ├── stake/
        │   ├── stake.prv         # Stake private key (extended format)
        │   ├── stake.skey        # Stake signing key (Eternl/cardano-cli format)
        │   ├── stake.pub         # Stake public key (bech32)
        │   ├── stake.pub.hex     # Stake public key (64-char hex)
        │   └── stake.addr        # Stake address
        └── payment/
            ├── 0/
            │   ├── payment.prv
            │   ├── payment.skey  # Payment signing key (Eternl format)
            │   ├── payment.pub
            │   ├── payment.pub.hex
            │   ├── enterprise.addr
            │   └── delegation.addr
            ├── 1/
            │   └── ...
            └── {I}/
                └── ...

SECURITY WARNING:
    This script stores private keys in plain text files. Only use for:
    - Development and testing
    - Educational purposes
    - Non-production environments

    DO NOT use for real funds on mainnet without proper key management!

EOF
}

#==============================================================================
# Utility Functions
#==============================================================================

log() {
    if [ "$QUIET_MODE" = false ]; then
        echo "$@"
    fi
}

log_step() {
    if [ "$QUIET_MODE" = false ]; then
        echo ""
        echo "========================================="
        echo "$@"
        echo "========================================="
    fi
}

log_success() {
    if [ "$QUIET_MODE" = false ]; then
        echo "✓ $@"
    fi
}

log_error() {
    echo "ERROR: $@" >&2
}

validate_network() {
    case "$1" in
        mainnet|testnet|preview|preprod)
            return 0
            ;;
        *)
            log_error "Invalid network: $1"
            log_error "Valid options: mainnet, testnet, preview, preprod"
            return 1
            ;;
    esac
}

validate_mnemonic_size() {
    case "$1" in
        12|15|18|21|24)
            return 0
            ;;
        *)
            log_error "Invalid mnemonic size: $1"
            log_error "Valid options: 12, 15, 18, 21, 24"
            return 1
            ;;
    esac
}

validate_number() {
    local value=$1
    local min=$2
    local max=$3
    local name=$4

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        log_error "$name must be a number"
        return 1
    fi

    if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
        log_error "$name must be between $min and $max"
        return 1
    fi

    return 0
}

check_dependencies() {
    # Check cardano-address binary
    if [ ! -f "$CARDANO_ADDRESS" ]; then
        log_error "cardano-address binary not found at: $CARDANO_ADDRESS"
        log_error "Please ensure cardano-address is built and in the script directory"
        exit 1
    fi

    if [ ! -x "$CARDANO_ADDRESS" ]; then
        log_error "cardano-address is not executable"
        log_error "Run: chmod +x $CARDANO_ADDRESS"
        exit 1
    fi

    # Check cardano-cli binary
    if [ ! -f "$CARDANO_CLI" ]; then
        log_error "cardano-cli binary not found at: $CARDANO_CLI"
        log_error "cardano-cli is required to generate .skey files for Eternl wallet"
        exit 1
    fi

    if [ ! -x "$CARDANO_CLI" ]; then
        log_error "cardano-cli is not executable"
        exit 1
    fi

    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed (required for extracting hex public keys)"
        log_error "Install with: sudo apt-get install jq (Debian/Ubuntu)"
        log_error "            or: sudo yum install jq (RedHat/CentOS)"
        log_error "            or: brew install jq (macOS)"
        exit 1
    fi
}

#==============================================================================
# Argument Parsing
#==============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--network)
                NETWORK="$2"
                validate_network "$NETWORK" || exit 1
                shift 2
                ;;
            -s|--size)
                MNEMONIC_SIZE="$2"
                validate_mnemonic_size "$MNEMONIC_SIZE" || exit 1
                shift 2
                ;;
            -a|--accounts)
                NUM_ACCOUNTS="$2"
                validate_number "$NUM_ACCOUNTS" 0 100 "Number of accounts" || exit 1
                shift 2
                ;;
            -d|--addresses)
                NUM_ADDRESSES="$2"
                validate_number "$NUM_ADDRESSES" 1 50 "Number of addresses" || exit 1
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -m|--mnemonic)
                EXISTING_MNEMONIC="$2"
                if [ ! -f "$EXISTING_MNEMONIC" ]; then
                    log_error "Mnemonic file not found: $EXISTING_MNEMONIC"
                    exit 1
                fi
                shift 2
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done
}

#==============================================================================
# Main Wallet Generation Functions
#==============================================================================

generate_or_load_mnemonic() {
    log_step "[1/6] Recovery Phrase (Mnemonic)"

    # Check if mnemonic already exists in output directory
    if [ -f "$OUTPUT_DIR/mnemonic.txt" ]; then
        log "Found existing mnemonic in output directory"
        log "Using existing mnemonic from: $OUTPUT_DIR/mnemonic.txt"
        MNEMONIC=$(cat "$OUTPUT_DIR/mnemonic.txt")

        # Validate mnemonic word count
        WORD_COUNT=$(echo "$MNEMONIC" | wc -w)
        if ! validate_mnemonic_size "$WORD_COUNT"; then
            log_error "Invalid mnemonic word count: $WORD_COUNT"
            exit 1
        fi

        log_success "Loaded existing mnemonic (will not overwrite)"
        if [ "$QUIET_MODE" = false ]; then
            echo "Mnemonic word count: $WORD_COUNT words"
        fi
        return 0
    fi

    # If --mnemonic flag was provided, use that
    if [ -n "$EXISTING_MNEMONIC" ]; then
        log "Using mnemonic from: $EXISTING_MNEMONIC"
        MNEMONIC=$(cat "$EXISTING_MNEMONIC")

        # Validate mnemonic word count
        WORD_COUNT=$(echo "$MNEMONIC" | wc -w)
        if ! validate_mnemonic_size "$WORD_COUNT"; then
            log_error "Invalid mnemonic word count: $WORD_COUNT"
            exit 1
        fi
    else
        # Generate new mnemonic
        log "Generating $MNEMONIC_SIZE-word recovery phrase..."
        MNEMONIC=$("$CARDANO_ADDRESS" recovery-phrase generate --size "$MNEMONIC_SIZE")
    fi

    # Save the mnemonic
    echo "$MNEMONIC" > "$OUTPUT_DIR/mnemonic.txt"
    chmod 600 "$OUTPUT_DIR/mnemonic.txt"

    log_success "Mnemonic saved to: $OUTPUT_DIR/mnemonic.txt"
    if [ "$QUIET_MODE" = false ]; then
        echo "Mnemonic: $MNEMONIC"
    fi
}

generate_root_key() {
    log_step "[2/6] Root Private Key"
    log "Converting mnemonic to root private key (Shelley style)..."

    echo "$MNEMONIC" | "$CARDANO_ADDRESS" key from-recovery-phrase Shelley > "$OUTPUT_DIR/root.prv"
    chmod 600 "$OUTPUT_DIR/root.prv"

    log_success "Root key saved to: $OUTPUT_DIR/root.prv"
}

generate_account_keys() {
    local account_num=$1
    local account_dir="$OUTPUT_DIR/account-$account_num"

    log "  Account $account_num (m/1852H/1815H/${account_num}H)..."

    mkdir -p "$account_dir"

    # Derive account private key
    cat "$OUTPUT_DIR/root.prv" | \
        "$CARDANO_ADDRESS" key child "1852H/1815H/${account_num}H" > "$account_dir/account.prv"
    chmod 600 "$account_dir/account.prv"

    # Derive account public key
    cat "$account_dir/account.prv" | \
        "$CARDANO_ADDRESS" key public --with-chain-code > "$account_dir/account.pub"

    # Extract hex public key
    cat "$account_dir/account.pub" | \
        "$CARDANO_ADDRESS" key inspect | \
        jq -r '.extended_key' > "$account_dir/account.pub.hex"

    log_success "  Account $account_num keys generated"
}

generate_stake_key() {
    local account_num=$1
    local account_dir="$OUTPUT_DIR/account-$account_num"
    local stake_dir="$account_dir/stake"

    mkdir -p "$stake_dir"

    # Derive stake private key (path: /2/0)
    cat "$account_dir/account.prv" | \
        "$CARDANO_ADDRESS" key child "2/0" > "$stake_dir/stake.prv"
    chmod 600 "$stake_dir/stake.prv"

    # Derive stake public key
    cat "$stake_dir/stake.prv" | \
        "$CARDANO_ADDRESS" key public --with-chain-code > "$stake_dir/stake.pub"

    # Extract hex public key
    cat "$stake_dir/stake.pub" | \
        "$CARDANO_ADDRESS" key inspect | \
        jq -r '.extended_key' > "$stake_dir/stake.pub.hex"

    # Generate stake address
    cat "$stake_dir/stake.pub" | \
        "$CARDANO_ADDRESS" address stake --network-tag "$NETWORK" > "$stake_dir/stake.addr"

    # Convert to .skey format for Eternl wallet
    "$CARDANO_CLI" key convert-cardano-address-key \
        --shelley-stake-key \
        --signing-key-file "$stake_dir/stake.prv" \
        --out-file "$stake_dir/stake.skey"
    chmod 600 "$stake_dir/stake.skey"

    log_success "  Stake key generated (m/1852H/1815H/${account_num}H/2/0)"
}

generate_payment_keys() {
    local account_num=$1
    local payment_index=$2
    local account_dir="$OUTPUT_DIR/account-$account_num"
    local payment_dir="$account_dir/payment/$payment_index"

    mkdir -p "$payment_dir"

    # Derive payment private key (path: /0/{index})
    cat "$account_dir/account.prv" | \
        "$CARDANO_ADDRESS" key child "0/$payment_index" > "$payment_dir/payment.prv"
    chmod 600 "$payment_dir/payment.prv"

    # Derive payment public key
    cat "$payment_dir/payment.prv" | \
        "$CARDANO_ADDRESS" key public --with-chain-code > "$payment_dir/payment.pub"

    # Extract hex public key
    cat "$payment_dir/payment.pub" | \
        "$CARDANO_ADDRESS" key inspect | \
        jq -r '.extended_key' > "$payment_dir/payment.pub.hex"

    # Convert to .skey format for Eternl wallet
    "$CARDANO_CLI" key convert-cardano-address-key \
        --shelley-payment-key \
        --signing-key-file "$payment_dir/payment.prv" \
        --out-file "$payment_dir/payment.skey"
    chmod 600 "$payment_dir/payment.skey"
}

generate_addresses() {
    local account_num=$1
    local payment_index=$2
    local account_dir="$OUTPUT_DIR/account-$account_num"
    local payment_dir="$account_dir/payment/$payment_index"
    local stake_dir="$account_dir/stake"

    # Generate enterprise address (payment only, no staking)
    cat "$payment_dir/payment.pub" | \
        "$CARDANO_ADDRESS" address payment --network-tag "$NETWORK" > \
        "$payment_dir/enterprise.addr"

    # Generate delegation address (payment + stake)
    local stake_key=$(cat "$stake_dir/stake.pub")
    cat "$payment_dir/payment.pub" | \
        "$CARDANO_ADDRESS" address payment --network-tag "$NETWORK" | \
        "$CARDANO_ADDRESS" address delegation "$stake_key" > \
        "$payment_dir/delegation.addr"

    log_success "  Payment address $payment_index (m/1852H/1815H/${account_num}H/0/$payment_index)"
}

process_accounts() {
    log_step "[3/6] Account Keys"

    if [ "$NUM_ACCOUNTS" -eq 0 ]; then
        log "Skipping account generation (--accounts 0)"
        return
    fi

    for ((i=0; i<NUM_ACCOUNTS; i++)); do
        generate_account_keys "$i"
    done
}

process_stake_keys() {
    log_step "[4/6] Stake Keys"

    if [ "$NUM_ACCOUNTS" -eq 0 ]; then
        log "Skipping stake key generation (no accounts)"
        return
    fi

    for ((i=0; i<NUM_ACCOUNTS; i++)); do
        generate_stake_key "$i"
    done
}

process_payment_keys() {
    log_step "[5/6] Payment Keys"

    if [ "$NUM_ACCOUNTS" -eq 0 ]; then
        log "Skipping payment key generation (no accounts)"
        return
    fi

    for ((i=0; i<NUM_ACCOUNTS; i++)); do
        log "  Account $i payment keys..."
        for ((j=0; j<NUM_ADDRESSES; j++)); do
            generate_payment_keys "$i" "$j"
        done
        log_success "  Account $i: $NUM_ADDRESSES payment keys generated"
    done
}

process_addresses() {
    log_step "[6/6] Addresses (Network: $NETWORK)"

    if [ "$NUM_ACCOUNTS" -eq 0 ]; then
        log "Skipping address generation (no accounts)"
        return
    fi

    for ((i=0; i<NUM_ACCOUNTS; i++)); do
        log "  Account $i addresses..."
        for ((j=0; j<NUM_ADDRESSES; j++)); do
            generate_addresses "$i" "$j"
        done
        log_success "  Account $i: $NUM_ADDRESSES addresses generated"
    done
}

generate_summary() {
    local summary_file="$OUTPUT_DIR/summary.txt"

    cat > "$summary_file" << EOF
========================================
Cardano HD Wallet Summary
========================================
Generated: $(date)
Network: $NETWORK
Mnemonic Size: $(echo "$MNEMONIC" | wc -w) words

========================================
Recovery Phrase
========================================
$MNEMONIC

IMPORTANT: Store this recovery phrase securely!
Anyone with this phrase can access your funds.

========================================
Derivation Paths (CIP-1852)
========================================
Root:           m
Purpose:        1852H (Shelley era)
Coin Type:      1815H (Cardano)
EOF

    if [ "$NUM_ACCOUNTS" -gt 0 ]; then
        echo "" >> "$summary_file"
        echo "========================================" >> "$summary_file"
        echo "Accounts Generated" >> "$summary_file"
        echo "========================================" >> "$summary_file"

        for ((i=0; i<NUM_ACCOUNTS; i++)); do
            local account_dir="$OUTPUT_DIR/account-$i"

            echo "" >> "$summary_file"
            echo "Account $i: m/1852H/1815H/${i}H" >> "$summary_file"
            echo "---" >> "$summary_file"
            echo "Stake Address: $(cat "$account_dir/stake/stake.addr")" >> "$summary_file"
            echo "" >> "$summary_file"
            echo "Payment Addresses:" >> "$summary_file"

            for ((j=0; j<NUM_ADDRESSES; j++)); do
                echo "  [$j] Enterprise: $(cat "$account_dir/payment/$j/enterprise.addr")" >> "$summary_file"
                echo "      Delegation: $(cat "$account_dir/payment/$j/delegation.addr")" >> "$summary_file"
                echo "      Path: m/1852H/1815H/${i}H/0/$j" >> "$summary_file"
                echo "" >> "$summary_file"
            done
        done
    fi

    cat >> "$summary_file" << EOF

========================================
File Structure
========================================
$OUTPUT_DIR/
├── mnemonic.txt              Recovery phrase
├── root.prv                  Root private key
├── summary.txt               This file
EOF

    for ((i=0; i<NUM_ACCOUNTS; i++)); do
        cat >> "$summary_file" << EOF
├── account-$i/
│   ├── account.prv           Account private key
│   ├── account.pub           Account public key (bech32)
│   ├── account.pub.hex       Account public key (hex)
│   ├── stake/
│   │   ├── stake.prv         Stake private key
│   │   ├── stake.skey        Stake signing key (Eternl format)
│   │   ├── stake.pub         Stake public key (bech32)
│   │   ├── stake.pub.hex     Stake public key (hex)
│   │   └── stake.addr        Stake address
│   └── payment/
EOF
        for ((j=0; j<NUM_ADDRESSES; j++)); do
            cat >> "$summary_file" << EOF
│       ├── $j/
│       │   ├── payment.prv
│       │   ├── payment.skey      (Eternl format)
│       │   ├── payment.pub
│       │   ├── payment.pub.hex
│       │   ├── enterprise.addr
│       │   └── delegation.addr
EOF
        done
    done

    cat >> "$summary_file" << EOF

========================================
Security Recommendations
========================================
1. Backup your mnemonic.txt file securely (offline)
2. Never share your private keys (.prv files)
3. Delete private keys when no longer needed
4. Use hardware wallets for mainnet funds
5. This tool is for development/testing only

========================================
Next Steps
========================================
1. For testnet funds, use a faucet:
   - Testnet: https://docs.cardano.org/cardano-testnet/tools/faucet/
   - Preview: https://docs.cardano.org/cardano-testnet/tools/faucet/

2. Check addresses with cardano-address:
   echo "addr..." | ./cardano-address address inspect

3. Use addresses in your application or wallet

========================================
EOF

    log_success "Summary saved to: $summary_file"
}

display_summary() {
    log_step "Wallet Generation Complete!"

    log ""
    log "Network:           $NETWORK"
    log "Accounts:          $NUM_ACCOUNTS"
    log "Addresses/Account: $NUM_ADDRESSES"
    log "Output Directory:  $OUTPUT_DIR"
    log ""

    if [ "$NUM_ACCOUNTS" -gt 0 ]; then
        log "Sample Addresses (Account 0):"
        log "  Stake:      $(cat "$OUTPUT_DIR/account-0/stake/stake.addr")"
        log "  Delegation: $(cat "$OUTPUT_DIR/account-0/payment/0/delegation.addr")"
        log "  Enterprise: $(cat "$OUTPUT_DIR/account-0/payment/0/enterprise.addr")"
        log ""
    fi

    log "All keys and addresses saved to: $OUTPUT_DIR/"
    log "Review summary.txt for complete details"
    log ""
    log "WARNING: Private keys are stored in plain text!"
    log "         Only use for development/testing purposes."
}

#==============================================================================
# Main Execution
#==============================================================================

main() {
    # Parse command-line arguments
    parse_arguments "$@"

    # Check for required dependencies
    check_dependencies

    # Show configuration
    log_step "Cardano HD Wallet Generator"
    log "Network:           $NETWORK"
    log "Mnemonic Size:     $MNEMONIC_SIZE words"
    log "Accounts:          $NUM_ACCOUNTS"
    log "Addresses/Account: $NUM_ADDRESSES"
    log "Output Directory:  $OUTPUT_DIR"

    if [ -n "$EXISTING_MNEMONIC" ]; then
        log "Using Mnemonic:    $EXISTING_MNEMONIC"
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Execute generation steps
    generate_or_load_mnemonic
    generate_root_key
    process_accounts
    process_stake_keys
    process_payment_keys
    process_addresses

    # Generate summary
    generate_summary

    # Display final summary
    display_summary
}

# Run main function with all arguments
main "$@"
