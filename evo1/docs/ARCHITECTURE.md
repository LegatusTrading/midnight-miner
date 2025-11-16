# MidnightMiner Architecture

**Version:** 1.0.0
**Date:** 2025-11-14
**Repository:** https://github.com/LegatusTrading/midnight-miner

---

## Overview

MidnightMiner is a Python-based mining solution for the Midnight blockchain's Scavenger Mine program, using the AshMaize Proof-of-Work algorithm. It achieves ~8 KH/s per 8-core VPS while supporting BIP39 mnemonic generation for full wallet portability.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         MidnightMiner                           │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │              Main Process (miner.py)                   │   │
│  │                                                         │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐ │   │
│  │  │  Challenge   │  │   Wallet     │  │  Solution   │ │   │
│  │  │  Manager     │  │  Manager     │  │  Submitter  │ │   │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬──────┘ │   │
│  │         │                  │                  │         │   │
│  │         │                  │                  │         │   │
│  │         ▼                  ▼                  ▼         │   │
│  │  ┌────────────────────────────────────────────────┐   │   │
│  │  │         Worker Pool (8 workers)                │   │   │
│  │  │                                                 │   │   │
│  │  │  Worker 1  Worker 2  ...  Worker 8            │   │   │
│  │  │     │         │              │                 │   │   │
│  │  │     └─────────┴──────────────┘                │   │   │
│  │  │              │                                  │   │   │
│  │  │              ▼                                  │   │   │
│  │  │     ┌─────────────────┐                       │   │   │
│  │  │     │  Native AshMaize │                       │   │   │
│  │  │     │  Library (.so)   │                       │   │   │
│  │  │     └─────────────────┘                       │   │   │
│  │  └────────────────────────────────────────────────┘   │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │                  Data Storage                          │   │
│  │                                                         │   │
│  │  wallets.json  challenges.json  balances.json         │   │
│  └────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │  Scavenger Mine API     │
              │  sm.midnight.gd         │
              └─────────────────────────┘
```

---

## Core Components

### 1. Challenge Manager

**Responsibilities:**
- Fetch available challenges from API
- Parse challenge parameters (difficulty, deadline)
- Queue challenges for workers
- Filter out expired or too-difficult challenges

**Key Functions:**
```python
def fetch_challenges():
    """Fetch active challenges from Scavenger Mine API."""
    response = requests.get("https://sm.midnight.gd/api/challenges")
    return response.json()

def select_best_challenge(wallet_address):
    """Select optimal challenge based on difficulty and deadline."""
    challenges = fetch_challenges()
    # Filter by deadline (2-hour buffer)
    valid = [c for c in challenges if c['deadline'] > now() + 7200]
    # Sort by difficulty (easiest first)
    return sorted(valid, key=lambda x: x['difficulty'])[0]
```

### 2. Wallet Manager

**Responsibilities:**
- Generate wallets with BIP39 mnemonics
- Manage wallet rotation
- Store wallet credentials securely
- Derive Cardano payment keys

**Key Functions:**
```python
def generate_wallet_with_mnemonic():
    """Generate Cardano wallet with 15-word BIP39 mnemonic."""
    from mnemonic import Mnemonic

    mnemo = Mnemonic("english")
    mnemonic_phrase = mnemo.generate(strength=160)  # 15 words
    seed = mnemo.to_seed(mnemonic_phrase)

    # Derive keys using CIP-1852 path: m/1852'/1815'/0'/0/0
    root_key = derive_root_key(seed)
    payment_key = derive_payment_key(root_key, path="m/1852'/1815'/0'/0/0")

    return {
        'mnemonic': mnemonic_phrase,
        'payment_key': payment_key.to_hex(),
        'verification_key': payment_key.to_verification_key().to_hex(),
        'address': to_address(payment_key.to_verification_key())
    }
```

**Data Structure (wallets.json):**
```json
[
  {
    "address": "addr1v8c24gzvlcq702uj6m7s0nl0m9qjdhm7a7zln47rd2tqxnsyg65k6",
    "mnemonic": "nation agree scatter keen merry drum burger cash truly appear spy alpha multiply when second",
    "payment_key": "58c2040a3f0e2c8b1a4d6f9e3a7c5b2d8e4f1a6c9b3e7d2f5a8c1b4e7d3a6c9b",
    "verification_key": "7a31b4c6d8e2f5a9c1b4d7e3a6c9b2e5d8f1a4c7b9e3d6f2a5c8b1e4d7a3c6",
    "created_at": "2025-11-13T22:01:03.300122+00:00"
  }
]
```

### 3. Solution Submitter

**Responsibilities:**
- Submit valid solutions to API
- Handle response codes and errors
- Track submission statistics
- Update balance snapshots

**Key Functions:**
```python
def submit_solution(wallet_address, challenge_id, nonce, hash_result):
    """Submit mining solution to Scavenger Mine API."""
    payload = {
        'wallet': wallet_address,
        'challenge': challenge_id,
        'nonce': nonce,
        'hash': hash_result
    }

    response = requests.post(
        "https://sm.midnight.gd/api/submit",
        json=payload,
        headers={'Content-Type': 'application/json'}
    )

    if response.status_code == 200:
        log_solution_accepted(wallet_address, challenge_id)
        update_balance_snapshot()
        return True
    else:
        log_solution_rejected(wallet_address, response.status_code)
        return False
```

### 4. Worker Pool

**Responsibilities:**
- Parallel challenge solving
- Thread management
- Progress tracking
- CPU utilization optimization

**Implementation:**
```python
def worker_thread(worker_id, challenge_queue):
    """Worker thread that processes challenges."""
    while True:
        challenge = challenge_queue.get()
        wallet = select_wallet_for_challenge(challenge)

        # Call native AshMaize library
        result = solve_challenge(
            challenge_id=challenge['id'],
            difficulty=challenge['difficulty'],
            deadline=challenge['deadline'],
            wallet_address=wallet['address']
        )

        if result['success']:
            submit_solution(
                wallet['address'],
                challenge['id'],
                result['nonce'],
                result['hash']
            )
```

### 5. Native AshMaize Library

**Responsibilities:**
- High-performance VM execution
- ROM generation (Argon2Hprime)
- Hash computation
- Nonce searching

**Interface:**
```python
# Python wrapper for native library
import ctypes

ashmaize_lib = ctypes.CDLL('./libs/linux-x64/ashmaize_py.so')

def solve_challenge(challenge_id, difficulty, deadline, wallet_address):
    """Call native AshMaize solver."""
    result = ashmaize_lib.ashmaize_solve(
        c_char_p(challenge_id.encode()),
        c_uint32(difficulty),
        c_uint64(deadline),
        c_char_p(wallet_address.encode())
    )
    return result
```

---

## Data Flow

### Mining Cycle

```
1. Fetch Challenges
   │
   ├─► Parse challenge parameters
   ├─► Filter by deadline (> 2 hours remaining)
   ├─► Sort by difficulty (easiest first)
   │
   ▼
2. Select Wallet
   │
   ├─► Check wallet hasn't solved this challenge
   ├─► Rotate to next available wallet
   │
   ▼
3. Solve Challenge
   │
   ├─► Generate ROM (Argon2Hprime)
   ├─► Execute AshMaize VM
   ├─► Search for valid nonce
   │
   ▼
4. Submit Solution
   │
   ├─► POST to API endpoint
   ├─► Handle response
   │   ├─► 200: Solution accepted ✅
   │   ├─► 409: Already solved
   │   └─► 400: Invalid solution ❌
   │
   ▼
5. Update State
   │
   ├─► Log solution
   ├─► Update balance snapshot
   ├─► Rotate to next wallet
   │
   └─► Return to step 1
```

### Data Persistence

**wallets.json:**
- Generated once during initial setup
- Contains BIP39 mnemonics and keys
- **CRITICAL:** Must be backed up regularly

**challenges.json:**
- Updated every fetch cycle
- Stores challenge history and state
- Can be regenerated if lost

**balances.json:**
- Updated after each solution
- Tracks NIGHT token accumulation
- Used for performance monitoring

---

## BIP39 Implementation

### Mnemonic Generation

**Standard:** BIP39 (Bitcoin Improvement Proposal 39)
**Word Count:** 15 words (160 bits entropy)
**Derivation Path:** CIP-1852 (Cardano Improvement Proposal)

### Key Derivation

```
Mnemonic (15 words)
    │
    ├─► PBKDF2-HMAC-SHA512
    │
    ▼
Root Seed (512 bits)
    │
    ├─► BIP32 HD derivation
    │
    ▼
Master Key
    │
    ├─► Path: m/1852'/1815'/0'/0/0
    │                │    │    │  │  │
    │                │    │    │  │  └─ Address Index (0)
    │                │    │    │  └──── Change (0 = external)
    │                │    │    └─────── Account (0)
    │                │    └──────────── Coin Type (1815 = ADA)
    │                └───────────────── Purpose (1852 = CIP-1852)
    │
    ▼
Payment Key Pair
    │
    ├─► Private Key (signing)
    ├─► Public Key (verification)
    │
    ▼
Cardano Address (Bech32)
    │
    └─► addr1v8c24gzvlcq702uj6m7s0nl0m9qjdhm7a7zln47rd2tqxnsyg65k6
```

### Wallet Recovery

**From Mnemonic:**
1. User enters 15-word phrase in NuFi/Eternl/Daedalus
2. Wallet software derives keys using CIP-1852
3. Generates same Cardano address
4. Full access to NIGHT tokens restored

---

## Performance Characteristics

### Hash Rate Breakdown

**8-core VPS (AMD EPYC 7543):**
- **Total:** ~8.4 KH/s
- **Per Worker:** ~1,050 H/s
- **CPU Usage:** 800% (all 8 cores at 100%)
- **Memory:** ~10 GB (mostly for ROM generation)

### Bottlenecks

1. **ROM Generation:** Most CPU-intensive operation
   - Uses Argon2Hprime algorithm
   - Requires ~1 GB RAM per worker
   - Benefits from CPU cache

2. **VM Execution:** Secondary bottleneck
   - 64-bit register operations
   - Random memory access patterns
   - Limited by cache misses

3. **Network I/O:** Minimal impact
   - Challenge fetching: ~1 request/minute
   - Solution submission: ~1 request/solution
   - Total bandwidth: <1 MB/hour

### Optimization Strategies

1. **Smart Challenge Selection**
   - Target low-difficulty challenges
   - Filter by time-to-deadline
   - Result: +20% solution rate

2. **Address Rotation**
   - One solution per address per challenge
   - 12 wallets = 12x more opportunities
   - Result: +50% solution rate

3. **Persistent State**
   - Save challenge history
   - Avoid re-solving
   - Result: No wasted work

---

## Security Considerations

### Private Key Management

**Storage:**
- Keys stored in `wallets.json` (plaintext)
- File permissions: 600 (owner read/write only)
- Location: `/root/MidnightMiner/wallets.json`

**Backup Strategy:**
- Automated backups every 4-6 hours
- Encrypted storage recommended
- Multiple backup locations

**Recovery:**
- BIP39 mnemonics enable recovery without wallets.json
- Write mnemonics on paper/metal for offline backup
- Never share mnemonics with anyone

### API Security

**Authentication:**
- No API keys required
- Wallet address serves as identity
- Solutions verified cryptographically

**Rate Limiting:**
- Challenge fetching: No limit
- Solution submission: Limited by solving speed
- No risk of API ban

---

## Deployment Architecture

### Single VPS

```
┌──────────────────────────────┐
│   VPS (8 cores, 32GB RAM)   │
│                              │
│  ┌────────────────────────┐ │
│  │    MidnightMiner       │ │
│  │    (8 workers)         │ │
│  │                        │ │
│  │    Hash Rate: 8.4 KH/s │ │
│  │    Solutions: ~96/day  │ │
│  └────────────────────────┘ │
│                              │
│  Cost: €5.23/day            │
│  ROI: ~18 NIGHT/day profit  │
└──────────────────────────────┘
```

### Multi-VPS (Scalable)

```
┌──────────┐  ┌──────────┐  ┌──────────┐
│  VPS4    │  │  VPS5    │  │  VPS6    │
│  8 cores │  │  8 cores │  │  8 cores │
│          │  │          │  │          │
│  8.4KH/s │  │  8.3KH/s │  │  8.5KH/s │
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │            │            │
     └────────────┼────────────┘
                  │
           ┌──────▼──────┐
           │  Scavenger  │
           │  Mine API   │
           └─────────────┘

Total: ~25 KH/s, ~290 solutions/day
Cost: €15.69/day, Profit: ~50 NIGHT/day
```

---

## Monitoring and Maintenance

### Key Metrics

**Performance:**
- Hash rate per worker
- Solutions per hour
- Success rate (%)

**System:**
- CPU usage (%)
- Memory usage (GB)
- Disk space

**Mining:**
- NIGHT balance
- Solutions by wallet
- Challenge difficulty trends

### Logging

**Log Levels:**
- INFO: Normal operations
- WARNING: Recoverable errors
- ERROR: Submission failures
- DEBUG: Detailed trace (disabled in production)

**Log Rotation:**
- Max size: 100 MB
- Keep: 7 days
- Compress: gzip

---

## Future Enhancements

### Planned Features

1. **GPU Acceleration**
   - Use CUDA/OpenCL for ROM generation
   - Expected: 3-5x hash rate increase

2. **Challenge Prediction**
   - ML model for difficulty forecasting
   - Optimize wallet allocation

3. **Automated Monitoring**
   - Grafana dashboard
   - SMS/Email alerts
   - Auto-restart on failure

4. **Historical Mining (VPS6)**
   - 2-hour deadline buffer
   - Challenge accumulation
   - Expected: +20% solutions

---

## References

- **AshMaize Algorithm:** https://github.com/circadian-risk/ce-ashmaize
- **BIP39 Standard:** https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki
- **CIP-1852:** https://cips.cardano.org/cips/cip1852/
- **Midnight Docs:** https://docs.midnight.network/

---

**Last Updated:** 2025-11-14
**Version:** 1.0.0
**Maintainer:** LegatusTrading
