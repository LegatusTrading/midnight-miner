#!/bin/bash
# Install systemd service for midnight-miner
# Run this script on the VPS as root

set -e

MINER_DIR="/root/midnight-miner"

echo "Installing midnight-miner systemd service..."
echo "Miner directory: $MINER_DIR"

# Create systemd service file
tee /etc/systemd/system/midnight-miner.service > /dev/null <<EOF
[Unit]
Description=Midnight NIGHT Token Miner
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$MINER_DIR
ExecStart=$MINER_DIR/.venv/bin/python $MINER_DIR/miner.py --workers 8 --wallets 16 --no-donation
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Environment
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Enabling midnight-miner service..."
systemctl enable midnight-miner

echo "Service installation complete!"
echo ""
echo "To start mining:"
echo "  systemctl start midnight-miner"
echo ""
echo "To check status:"
echo "  systemctl status midnight-miner"
echo ""
echo "To view logs:"
echo "  journalctl -u midnight-miner -f"
