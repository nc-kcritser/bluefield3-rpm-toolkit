#!/bin/bash
# setup-spectrum-x-rhel.sh
# Setup script to configure Spectrum-X RoCE accelerations at boot
# For RHEL/Rocky/Alma Linux (RPM-based distributions)
# Based on NVIDIA's Ubuntu networkd-dispatcher script

echo "=========================================="
echo "Spectrum-X RoCE Boot Configuration Setup"
echo "For RHEL/Rocky Linux (RPM-based distros)"
echo "=========================================="
echo ""

# Define interfaces (edit this list as needed)
INTERFACES="ens32f0np0 ens33f0np0 ens34f0np0 ens35f0np0 ens36f0np0 ens37f0np0 ens38f0np0 ens39f0np0"

# 1. Create the configuration script
echo "Creating configuration script..."
sudo tee /usr/local/bin/configure-spectrum-x-rhel.sh > /dev/null << EOF
#!/bin/bash
# Configure Spectrum-X RoCE Accelerations on BlueField-3 cards
# RHEL/Rocky Linux version (systemd-based)

# List of BlueField-3 interfaces
INTERFACES="$INTERFACES"

for IFACE in \$INTERFACES; do
    # Check if interface exists
    if [ ! -d "/sys/class/net/\$IFACE" ]; then
        echo "Interface \$IFACE not found, skipping..."
        continue
    fi
    
    # Get PCI address from interface
    PCI_ADDRESS=\$(cat /sys/class/net/\$IFACE/device/uevent 2>/dev/null | grep PCI_SLOT_NAME | cut -d'=' -f 2)
    
    if [ -z "\$PCI_ADDRESS" ]; then
        echo "Could not get PCI address for \$IFACE, skipping..."
        continue
    fi
    
    echo "Configuring Spectrum-X on interface \$IFACE (PCI: \$PCI_ADDRESS)..."
    
    /usr/bin/mlxreg -d \$PCI_ADDRESS --reg_name ROCE_ACCL \
        --set roce_adp_retrans_en=0x1,roce_tx_window_en=0x1,roce_slow_restart_en=0x0,roce_slow_restart_idle_en=0x0,adaptive_routing_forced_en=0x1 \
        --yes
done

echo "Spectrum-X RoCE accelerations configured on all interfaces"
EOF

# 2. Make it executable
echo "Making script executable..."
sudo chmod +x /usr/local/bin/configure-spectrum-x-rhel.sh

# 3. Create the systemd service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/spectrum-x-roce.service > /dev/null << 'EOF'
[Unit]
Description=Configure Spectrum-X RoCE Accelerations on BlueField-3 (RHEL)
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/configure-spectrum-x-rhel.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 4. Enable and start the service
echo "Enabling and starting service..."
sudo systemctl daemon-reload
sudo systemctl enable spectrum-x-roce.service
sudo systemctl start spectrum-x-roce.service

echo ""
echo "Service status:"
sudo systemctl status spectrum-x-roce.service --no-pager

# 5. Verify it worked
echo ""
echo "=========================================="
echo "Verifying configuration..."
echo "=========================================="
for IFACE in $INTERFACES; do
    if [ -d "/sys/class/net/$IFACE" ]; then
        PCI_ADDRESS=$(cat /sys/class/net/$IFACE/device/uevent 2>/dev/null | grep PCI_SLOT_NAME | cut -d'=' -f 2)
        echo "=== $IFACE ($PCI_ADDRESS) ==="
        sudo mlxreg -d $PCI_ADDRESS --get --reg_name ROCE_ACCL | grep -E "roce_tx_window_en|adaptive_routing_forced_en" | grep -v field_select
        echo ""
    fi
done

echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "The Spectrum-X RoCE accelerations will now be configured automatically on every boot."
echo "Platform: RHEL/Rocky Linux (RPM-based, systemd service)"
echo "Script: /usr/local/bin/configure-spectrum-x-rhel.sh"
echo "Service: spectrum-x-roce.service"
echo "Configured interfaces: $INTERFACES"
echo ""
echo "To check service status: sudo systemctl status spectrum-x-roce.service"
echo "To view logs: sudo journalctl -u spectrum-x-roce.service"
echo ""
echo "Note: Based on NVIDIA's Ubuntu networkd-dispatcher script,"
echo "      adapted for RHEL/Rocky using systemd service instead."
echo ""
