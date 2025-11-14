#!/bin/bash
# Quick status summary for all VPSs

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  MidnightMiner - All VPS Status Summary"
echo "=========================================="
echo ""

# Find all VPS configs (exclude local and examples)
CONFIGS=$(ls config/*.conf 2>/dev/null | grep -v local.conf | grep -v .example || true)

if [ -z "$CONFIGS" ]; then
    echo "No VPS configurations found"
    exit 1
fi

# Arrays to collect totals
declare -a VPS_NAMES
declare -a UPTIMES
declare -a SOLUTIONS
declare -a UPTIMES_SECONDS

TOTAL_SOLUTIONS=0
TOTAL_UPTIME_SECONDS=0

echo -e "${CYAN}VPS      Status      Uptime       Solutions${NC}"
echo "------------------------------------------------"

for config_file in $CONFIGS; do
    # Extract VPS name from config filename
    VPS_NAME=$(basename "$config_file" .conf)

    # Load config (bash-style KEY=VALUE)
    source "$config_file"

    # Query VPS
    SSH_HOST="root@$HOSTNAME"

    # Check if service is running
    IS_RUNNING=$(ssh "$SSH_HOST" "systemctl is-active midnight-miner 2>/dev/null || echo inactive")

    if [ "$IS_RUNNING" = "active" ]; then
        STATUS="${GREEN}RUNNING ✓${NC}"

        # Get uptime in seconds
        UPTIME_SEC=$(ssh "$SSH_HOST" "systemctl show midnight-miner --property=ActiveEnterTimestampMonotonic --value 2>/dev/null || echo 0")
        CURRENT_MONOTONIC=$(ssh "$SSH_HOST" "cat /proc/uptime | awk '{print \$1 * 1000000}' 2>/dev/null || echo 0")

        # Calculate running time in seconds
        if [ "$UPTIME_SEC" != "0" ] && [ "$CURRENT_MONOTONIC" != "0" ]; then
            RUNNING_SECONDS=$(( (CURRENT_MONOTONIC - UPTIME_SEC) / 1000000 ))
        else
            # Fallback: try to parse from systemctl status
            RUNNING_SECONDS=$(ssh "$SSH_HOST" "systemctl status midnight-miner | grep 'Active:' | awk '{print \$8, \$9}' | sed 's/ago//'" 2>/dev/null || echo "0s")
            # Convert to seconds (rough approximation)
            if [[ "$RUNNING_SECONDS" == *"h"* ]]; then
                HOURS=$(echo "$RUNNING_SECONDS" | sed 's/h.*//')
                RUNNING_SECONDS=$((HOURS * 3600))
            elif [[ "$RUNNING_SECONDS" == *"min"* ]]; then
                MINS=$(echo "$RUNNING_SECONDS" | sed 's/min.*//')
                RUNNING_SECONDS=$((MINS * 60))
            else
                RUNNING_SECONDS=0
            fi
        fi

        # Get solution count
        SOLUTION_COUNT=$(ssh "$SSH_HOST" "journalctl -u midnight-miner --no-pager 2>/dev/null | grep -c 'Solution accepted' || echo 0")

        # Format uptime for display
        HOURS=$((RUNNING_SECONDS / 3600))
        MINS=$(( (RUNNING_SECONDS % 3600) / 60 ))
        UPTIME_DISPLAY="${HOURS}h ${MINS}m"

        # Store for totals
        TOTAL_SOLUTIONS=$((TOTAL_SOLUTIONS + SOLUTION_COUNT))
        TOTAL_UPTIME_SECONDS=$((TOTAL_UPTIME_SECONDS + RUNNING_SECONDS))

    else
        STATUS="${YELLOW}STOPPED${NC}"
        UPTIME_DISPLAY="-"
        SOLUTION_COUNT="0"
        RUNNING_SECONDS=0
    fi

    # Display row
    printf "%-8s %-15b %-12s %-10s\n" "$VPS_NAME" "$STATUS" "$UPTIME_DISPLAY" "$SOLUTION_COUNT"
done

echo "------------------------------------------------"

# Calculate totals
TOTAL_HOURS=$((TOTAL_UPTIME_SECONDS / 3600))
TOTAL_MINS=$(( (TOTAL_UPTIME_SECONDS % 3600) / 60 ))

# Average solutions per hour per server
# Total time is already the sum of all server uptimes
if [ "$TOTAL_UPTIME_SECONDS" -gt 0 ]; then
    AVG_SOLUTIONS_PER_HOUR=$(echo "scale=2; $TOTAL_SOLUTIONS * 3600 / $TOTAL_UPTIME_SECONDS" | bc)
else
    AVG_SOLUTIONS_PER_HOUR="0"
fi

echo ""
echo -e "${CYAN}TOTALS:${NC}"
echo "  Total Solutions:       $TOTAL_SOLUTIONS"
echo "  Total Running Time:    ${TOTAL_HOURS}h ${TOTAL_MINS}m"
echo "  Avg. Solutions/Hour:   $AVG_SOLUTIONS_PER_HOUR"
echo ""
echo "=========================================="
echo ""
