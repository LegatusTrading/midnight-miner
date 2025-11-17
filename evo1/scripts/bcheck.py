#!/usr/bin/env python3
"""
Better Check (bcheck) - Comprehensive wallet and mining status checker

This script runs LOCALLY and connects to the remote server via SSH to:
- Discover ALL seed phrases and wallets on the server
- Fetch solution counts from challenges.json
- Query real API statistics using local browser automation
- Display comprehensive status

Usage: ./scripts/bcheck.py <hostname> [--api]

Example:
  ./scripts/bcheck.py 51.159.160.161
  ./scripts/bcheck.py 51.159.160.161 --api
"""
import json
import sys
import subprocess
import os
import time
from datetime import datetime, timezone
from pathlib import Path
import requests

# Try to import playwright for browser-based API access
try:
    from playwright.sync_api import sync_playwright
    PLAYWRIGHT_AVAILABLE = True
except ImportError:
    PLAYWRIGHT_AVAILABLE = False

# Color codes for terminal output
class Colors:
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    BOLD = '\033[1m'
    END = '\033[0m'

def run_remote_cmd(hostname, cmd):
    """Run shell command on remote server via SSH and return output"""
    try:
        ssh_cmd = f'ssh root@{hostname} "{cmd}"'
        result = subprocess.run(ssh_cmd, shell=True, capture_output=True, text=True, timeout=10)
        return result.stdout.strip()
    except Exception as e:
        return f"Error: {e}"

def find_all_mnemonics(hostname, base_dir="/root/midnight-miner"):
    """Discover all seed phrases on the remote server via SSH"""
    mnemonics = []

    # Primary location
    primary_mnemonic_path = f"{base_dir}/hd-wallets/mnemonic.txt"
    mnemonic_content = run_remote_cmd(hostname, f"cat {primary_mnemonic_path} 2>/dev/null")
    if mnemonic_content and not mnemonic_content.startswith("Error"):
        mnemonics.append({
            'mnemonic': mnemonic_content,
            'location': primary_mnemonic_path,
            'label': 'Current HD Wallet'
        })

    # Search for backup mnemonics
    backup_paths = run_remote_cmd(hostname, f"find {base_dir} -name 'mnemonic*.txt' 2>/dev/null")
    if backup_paths and not backup_paths.startswith("Error"):
        for path in backup_paths.split('\n'):
            if path and path != primary_mnemonic_path:
                mnemonic_content = run_remote_cmd(hostname, f"cat {path} 2>/dev/null")
                if mnemonic_content and not mnemonic_content.startswith("Error"):
                    if mnemonic_content not in [m['mnemonic'] for m in mnemonics]:
                        mnemonics.append({
                            'mnemonic': mnemonic_content,
                            'location': path,
                            'label': 'Backup'
                        })

    return mnemonics

def find_all_wallets(hostname, base_dir="/root/midnight-miner"):
    """Discover all wallet files on the remote server via SSH"""
    wallet_files = []

    # Primary location
    primary_wallet_path = f"{base_dir}/wallets.json"
    wallet_check = run_remote_cmd(hostname, f"test -f {primary_wallet_path} && echo exists")
    if wallet_check == "exists":
        wallet_files.append({
            'path': primary_wallet_path,
            'label': 'Current Wallets'
        })

    # Search for backup wallet files
    backup_paths = run_remote_cmd(hostname, f"find {base_dir} -name 'wallets*.json' 2>/dev/null")
    if backup_paths and not backup_paths.startswith("Error"):
        for path in backup_paths.split('\n'):
            if path and path != primary_wallet_path:
                wallet_files.append({
                    'path': path,
                    'label': 'Backup'
                })

    return wallet_files

def load_wallets_from_remote(hostname, file_path):
    """Load wallets from JSON file on remote server via SSH"""
    try:
        wallet_json = run_remote_cmd(hostname, f"cat {file_path} 2>/dev/null")
        if wallet_json and not wallet_json.startswith("Error"):
            return json.loads(wallet_json)
    except:
        pass
    return []

def load_solutions_from_remote(hostname, challenges_file="/root/midnight-miner/challenges.json"):
    """Load solution counts per wallet from challenges.json on remote server via SSH"""
    wallet_solutions = {}
    try:
        challenges_json = run_remote_cmd(hostname, f"cat {challenges_file} 2>/dev/null")
        if challenges_json and not challenges_json.startswith("Error"):
            challenges = json.loads(challenges_json)

            # Count solutions per wallet from challenges.json (persistent storage)
            for challenge_data in challenges.values():
                solved_by = challenge_data.get('solved_by', [])
                for addr in solved_by:
                    wallet_solutions[addr] = wallet_solutions.get(addr, 0) + 1
    except:
        pass

    return wallet_solutions

def derive_addresses_from_mnemonic(mnemonic, num_accounts=24):
    """Derive addresses from mnemonic to match with wallets"""
    # We'll use the first few words as a fingerprint
    words = mnemonic.split()
    return ' '.join(words[:4]) + ' ..'

def query_api_with_browser(address, browser_context):
    """Query API using browser context to bypass bot protection"""
    try:
        url = f"https://sm.midnight.gd/api/statistics/{address}"

        # Create a new page
        page = browser_context.new_page()

        # Navigate to the API endpoint
        response = page.goto(url, wait_until='networkidle', timeout=10000)

        if response and response.status == 200:
            # Get the JSON content from the page
            content = page.content()
            # Extract JSON from <pre> tag or body
            if '<pre>' in content:
                json_text = page.locator('pre').inner_text()
            else:
                json_text = page.locator('body').inner_text()

            data = json.loads(json_text)
            local = data.get('local', {})

            page.close()
            return {
                'crypto': local.get('crypto_receipts', 0),
                'night': local.get('night_allocation', 0)
            }

        page.close()
        return {'crypto': '?', 'night': '?'}
    except Exception as e:
        return {'crypto': 'ERR', 'night': 'ERR'}

def query_api_statistics(address, max_retries=3, browser_context=None):
    """Query API for real statistics with retry logic"""
    # If browser context is available, use it to bypass bot protection
    if browser_context:
        return query_api_with_browser(address, browser_context)

    # Otherwise fall back to regular requests (may be blocked)
    url = f"https://sm.midnight.gd/api/statistics/{address}"

    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Accept': 'application/json',
        'Referer': 'https://sm.midnight.gd/'
    }

    for attempt in range(max_retries):
        try:
            time.sleep(1)
            response = requests.get(url, headers=headers, timeout=10)
            if response.status_code == 200:
                data = response.json()
                local = data.get('local', {})
                return {
                    'crypto': local.get('crypto_receipts', 0),
                    'night': local.get('night_allocation', 0)
                }
            elif response.status_code == 429:
                if attempt < max_retries - 1:
                    time.sleep(3)
                    continue
                return {'crypto': 'RATE', 'night': 'LIMIT'}
            elif response.status_code == 403:
                return {'crypto': 'BOT', 'night': 'BLOCK'}
        except Exception as e:
            if attempt < max_retries - 1:
                time.sleep(2)

    return {'crypto': 'ERR', 'night': 'ERR'}

def get_mining_status(hostname):
    """Get synthetic mining status from remote server logs via SSH"""
    status = {
        'service_running': False,
        'uptime': '',
        'hash_rate': '',
        'workers': 0,
        'total_solutions': 0
    }

    # Check service status
    result = run_remote_cmd(hostname, "systemctl is-active midnight-miner")
    status['service_running'] = result == "active"

    if not status['service_running']:
        return status

    # Get uptime
    uptime_raw = run_remote_cmd(hostname, "systemctl show midnight-miner --property=ActiveEnterTimestamp --value")
    if uptime_raw:
        try:
            start_time = datetime.strptime(uptime_raw, "%a %Y-%m-%d %H:%M:%S %Z")
            uptime_seconds = (datetime.now() - start_time).total_seconds()
            hours = int(uptime_seconds // 3600)
            minutes = int((uptime_seconds % 3600) // 60)
            status['uptime'] = f"{hours}h {minutes}m"
        except:
            status['uptime'] = '?'

    # Get hash rate from logs
    hash_rate_raw = run_remote_cmd(hostname, "journalctl -u midnight-miner -n 50 --no-pager | grep 'Total Hash Rate' | tail -1")
    if hash_rate_raw:
        parts = hash_rate_raw.split()
        if len(parts) >= 2:
            status['hash_rate'] = f"{parts[-2]} {parts[-1]}"

    # Get total solutions
    solutions_raw = run_remote_cmd(hostname, "journalctl -u midnight-miner -n 100 --no-pager | grep 'Total Completed' | tail -1")
    if solutions_raw:
        parts = solutions_raw.split()
        if len(parts) >= 8:
            try:
                status['total_solutions'] = int(parts[7])
            except:
                pass

    # Get worker count from service file
    workers_raw = run_remote_cmd(hostname, "grep -oP '(?<=--workers )\\\\d+' /etc/systemd/system/midnight-miner.service")
    if workers_raw:
        try:
            status['workers'] = int(workers_raw)
        except:
            pass

    return status

def print_header(text):
    """Print section header"""
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*70}{Colors.END}")
    print(f"{Colors.BOLD}{Colors.BLUE}{text}{Colors.END}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'='*70}{Colors.END}\n")

def print_seed_section(seed_info, wallets, local_solutions=None, query_api=False, browser_context=None):
    """Print information for a seed phrase and its wallets"""
    print(f"{Colors.BOLD}Seed Phrase: {Colors.END}{seed_info['fingerprint']}")
    print(f"{Colors.BOLD}Location:    {Colors.END}{seed_info['location']}")
    print(f"{Colors.BOLD}Label:       {Colors.END}{seed_info['label']}")
    print(f"{Colors.BOLD}Addresses:   {Colors.END}{len(wallets)}")

    if not wallets:
        print(f"{Colors.YELLOW}No wallets found for this seed phrase{Colors.END}")
        return

    # Calculate totals
    total_solutions = 0
    total_crypto = 0.0
    total_night = 0.0

    print(f"\n{'#':<4} {'Address':<66} {'Sols':<6} {'Crypto':<10} {'NIGHT':<10}")
    print("-" * 100)

    for i, wallet in enumerate(wallets):
        addr = wallet['address']

        # Sols column ALWAYS uses local data from challenges.json (authoritative source)
        if local_solutions is not None:
            sols = local_solutions.get(addr, 0)
            total_solutions += sols
        else:
            sols = '?'

        # Crypto and NIGHT columns only populated when API mode is enabled
        if query_api:
            stats = query_api_statistics(addr, browser_context=browser_context)
            crypto = stats.get('crypto', '?')
            night = stats.get('night', '?')

            if isinstance(crypto, (int, float)):
                total_crypto += crypto
            if isinstance(night, (int, float)):
                total_night += night
        else:
            crypto = '-'
            night = '-'

        # Format output
        sols_str = str(sols)
        crypto_str = f"{crypto:.2f}" if isinstance(crypto, (int, float)) else str(crypto)
        night_str = f"{night:.2f}" if isinstance(night, (int, float)) else str(night)

        print(f"{i+1:<4} {addr:<66} {sols_str:<6} {crypto_str:<10} {night_str:<10}")

    # Show totals
    print("-" * 100)
    # Solutions total is always shown, crypto/night only in API mode
    crypto_total_str = f"{total_crypto:.2f}" if query_api else "-"
    night_total_str = f"{total_night:.2f}" if query_api else "-"
    print(f"{'TOTAL':<71} {total_solutions:<6} {crypto_total_str:<10} {night_total_str:<10}")

def print_mining_status(status):
    """Print synthetic mining status"""
    print_header("MINING STATUS")

    service_status = f"{Colors.GREEN}Running ✅{Colors.END}" if status['service_running'] else f"{Colors.RED}Stopped ❌{Colors.END}"
    print(f"{Colors.BOLD}Service:   {Colors.END}{service_status}")

    if status['service_running']:
        print(f"{Colors.BOLD}Uptime:    {Colors.END}{status['uptime']}")
        print(f"{Colors.BOLD}Hash Rate: {Colors.END}{status['hash_rate']}")
        print(f"{Colors.BOLD}Workers:   {Colors.END}{status['workers']}")
        print(f"{Colors.BOLD}Solutions: {Colors.END}{status['total_solutions']}")

def main():
    if len(sys.argv) < 2:
        print("Usage: ./scripts/bcheck.py <hostname> [--api]")
        print("Example: ./scripts/bcheck.py 51.159.160.161")
        sys.exit(1)

    hostname = sys.argv[1]

    print_header(f"BETTER CHECK - {hostname}")
    print(f"{Colors.BOLD}Generated: {Colors.END}{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")

    # Discover all seed phrases on remote server
    print(f"\n{Colors.BOLD}Discovering seed phrases on {hostname}...{Colors.END}")
    mnemonics = find_all_mnemonics(hostname)
    print(f"Found {len(mnemonics)} seed phrase(s)")

    # Discover all wallet files on remote server
    print(f"{Colors.BOLD}Discovering wallet files on {hostname}...{Colors.END}")
    wallet_files = find_all_wallets(hostname)
    print(f"Found {len(wallet_files)} wallet file(s)")

    # Group wallets by seed phrase (using fingerprint matching)
    seed_groups = []
    for mnemonic_info in mnemonics:
        fingerprint = derive_addresses_from_mnemonic(mnemonic_info['mnemonic'])

        # Find matching wallet file (for now, use current wallets.json)
        # TODO: Implement proper address derivation matching
        wallets = []
        for wallet_file in wallet_files:
            if 'Current' in wallet_file['label']:
                wallets = load_wallets_from_remote(hostname, wallet_file['path'])
                # Filter BASE addresses only
                wallets = [w for w in wallets if w['address'].startswith('addr1q')]
                break

        seed_groups.append({
            'fingerprint': fingerprint,
            'location': mnemonic_info['location'],
            'label': mnemonic_info['label'],
            'wallets': wallets
        })

    # Load local solutions from challenges.json on remote server (authoritative source)
    local_solutions = load_solutions_from_remote(hostname)

    # Check if API mode is enabled
    query_api = '--api' in sys.argv or '-a' in sys.argv

    # Create browser context if API mode is enabled and playwright is available (LOCAL)
    browser_context = None
    playwright_instance = None
    browser = None

    if query_api:
        if PLAYWRIGHT_AVAILABLE:
            try:
                print(f"{Colors.BOLD}Initializing local browser for API queries...{Colors.END}")
                playwright_instance = sync_playwright().start()
                browser = playwright_instance.chromium.launch(headless=True)
                browser_context = browser.new_context(
                    user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
                )
                print(f"{Colors.GREEN}Browser ready{Colors.END}")
            except Exception as e:
                print(f"{Colors.YELLOW}Warning: Could not start browser: {e}{Colors.END}")
                print(f"{Colors.YELLOW}Falling back to requests library{Colors.END}")
        else:
            print(f"{Colors.YELLOW}Warning: Playwright not available. Install with: pip install playwright && playwright install chromium{Colors.END}")

    try:
        # Print seed phrase sections
        for i, seed_info in enumerate(seed_groups):
            print_header(f"SEED PHRASE {i+1}")
            print_seed_section(seed_info, seed_info['wallets'], local_solutions=local_solutions,
                             query_api=query_api, browser_context=browser_context)

        # Print mining status from remote server
        status = get_mining_status(hostname)
        print_mining_status(status)

        if not query_api:
            print(f"\n{Colors.BOLD}Tip:{Colors.END} Use 'make bcka-s3' to query Crypto/NIGHT from API")
        print()
    finally:
        # Clean up browser resources
        if browser_context:
            browser_context.close()
        if browser:
            browser.close()
        if playwright_instance:
            playwright_instance.stop()

if __name__ == '__main__':
    main()
