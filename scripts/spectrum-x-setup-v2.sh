#!/bin/bash
set -euo pipefail

# =============================================================================
# Spectrum-X RoCE Configuration Installer
# RHEL/Rocky Linux — BlueField-3 / Spectrum-X
# Standalone systemd service method
# =============================================================================

# --- Define your interface list here -----------------------------------------
INTERFACES="ens32f0np0 ens33f0np0 ens34f0np0 ens35f0np0 ens36f0np0 ens37f0np0 ens38f0np0 ens39f0np0"
# -----------------------------------------------------------------------------

echo "=== Spectrum-X RoCE Configuration Installer ==="
echo "Method    : Standalone systemd service"
echo "Interfaces: $INTERFACES"
echo ""

# =============================================================================
# PART 1 — Write the configuration script
# =============================================================================
echo "Creating configuration script..."
sudo tee /usr/local/sbin/configure-spectrum-x-rhel.sh > /dev/null << EOF
#!/bin/bash
set -euo pipefail

# =============================================================================
# Configure Spectrum-X RoCE Accelerations on BlueField-3 cards
# RHEL/Rocky Linux version
#
# Usage: INTERFACES="ens32f0np0 ens33f0np0 ..." bash configure-spectrum-x-rhel.sh
#    or: edit INTERFACES below and run directly
# =============================================================================

MELLANOX=0x15b3
BLUEFIELD_3=0xa2dc
RDMA_TIMEOUT=5

# --- Define your interface list here -----------------------------------------
INTERFACES="\${INTERFACES:-$INTERFACES}"
# -----------------------------------------------------------------------------

for IFACE in \$INTERFACES; do

    echo "--- Checking \$IFACE ---"

    # --- Interface Existence Check -------------------------------------------
    if [ ! -d "/sys/class/net/\$IFACE" ]; then
        echo "Interface \$IFACE not found, skipping..."
        continue
    fi

    # --- Hardware Validation -------------------------------------------------
    VENDOR_ID=\$(cat /sys/class/net/\$IFACE/device/vendor 2>/dev/null || true)
    if [ "\$VENDOR_ID" != "\$MELLANOX" ]; then
        echo "Skipping \$IFACE — not an NVIDIA/Mellanox interface (vendor: \$VENDOR_ID)"
        continue
    fi

    DEVICE_ID=\$(cat /sys/class/net/\$IFACE/device/device 2>/dev/null || true)
    if [ "\$DEVICE_ID" != "\$BLUEFIELD_3" ]; then
        echo "Skipping \$IFACE — not a BlueField-3 device (device: \$DEVICE_ID)"
        continue
    fi

    # --- PCI Address Retrieval -----------------------------------------------
    PCI_ADDRESS=\$(cat /sys/class/net/\$IFACE/device/uevent 2>/dev/null | grep PCI_SLOT_NAME | cut -d'=' -f 2)

    if [ -z "\$PCI_ADDRESS" ]; then
        echo "Could not get PCI address for \$IFACE, skipping..."
        continue
    fi

    # --- RDMA Readiness Wait -------------------------------------------------
    echo "Waiting for RDMA device on \$IFACE..."
    TIMEOUT=0
    set +e
    while true; do
        /usr/bin/ls /sys/class/net/\$IFACE/device/infiniband/ &>/dev/null
        if [ \$? -eq 0 ]; then
            break
        fi
        if [ "\$TIMEOUT" -ge "\$RDMA_TIMEOUT" ]; then
            echo "ERROR: RDMA timeout — device not present for \$IFACE after \${RDMA_TIMEOUT}s, skipping..."
            continue 2
        fi
        sleep 1
        (( TIMEOUT++ ))
    done
    set -e

    # --- Gather Device Info --------------------------------------------------
    RDMA_DEVICE=\$(/usr/bin/ls /sys/class/net/\$IFACE/device/infiniband/ -AU | head -1)

    echo "Configuring interface : \$IFACE"
    echo "RDMA device           : \$RDMA_DEVICE"
    echo "PCI address           : \$PCI_ADDRESS"

    # --- RoCE Configuration --------------------------------------------------
    echo "Applying RoCE configuration..."
    if ! /usr/bin/mlnx_qos -i \$IFACE --pfc=0,0,0,1,0,0,0,0 --trust=dscp; then
        echo "ERROR: mlnx_qos failed on \$IFACE, skipping..."
        continue
    fi

    if ! /usr/sbin/cma_roce_tos -d \$RDMA_DEVICE -t 96; then
        echo "ERROR: cma_roce_tos failed on \$RDMA_DEVICE, skipping..."
        continue
    fi

    echo 96 > /sys/class/infiniband/\$RDMA_DEVICE/tc/1/traffic_class

    # --- Congestion Control --------------------------------------------------
    echo "Enabling Congestion Control..."
    for point in "rp" "np"; do
        for i in {0..7}; do
            echo 1 > /sys/class/net/\$IFACE/ecn/roce_\${point}/enable/\${i}
        done
    done

    # --- RoCE Accelerations --------------------------------------------------
    echo "Configuring RoCE Accelerations on \$IFACE (PCI: \$PCI_ADDRESS)..."
    if ! /usr/bin/mlxreg -d \$PCI_ADDRESS \\
        --reg_name ROCE_ACCL \\
        --set roce_adp_retrans_en=0x1,roce_tx_window_en=0x1,roce_slow_restart_en=0x0,roce_slow_restart_idle_en=0x0,adaptive_routing_forced_en=0x1 \\
        --yes; then
        echo "ERROR: mlxreg set failed on \$IFACE, skipping..."
        continue
    fi

    # --- Post-Write Verification ---------------------------------------------
    if /usr/bin/mlxreg -d \$PCI_ADDRESS --get --reg_name ROCE_ACCL \\
        | grep adaptive_routing_forced_en \\
        | grep -q 0x00000001; then
        echo "RoCE Accelerations successfully configured on \$IFACE"
    else
        echo "ERROR: Failed to verify RoCE Accelerations on \$IFACE — ensure DPU has Spectrum-X enabled"
        continue
    fi

    echo "Interface \$IFACE configured successfully"
    echo ""

done

echo "=== All interfaces processed ==="
EOF

sudo chmod 755 /usr/local/sbin/configure-spectrum-x-rhel.sh
sudo chown root:root /usr/local/sbin/configure-spectrum-x-rhel.sh
echo "Configuration script written to /usr/local/sbin/configure-spectrum-x-rhel.sh"
echo ""

# =============================================================================
# PART 2 — Write the systemd service unit
# =============================================================================
echo "Creating systemd service unit..."
sudo tee /etc/systemd/system/spectrum-x.service > /dev/null << 'EOF'
[Unit]
Description=Configure Spectrum-X RoCE Accelerations on BlueField-3 cards
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/configure-spectrum-x-rhel.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo "systemd service unit written to /etc/systemd/system/spectrum-x.service"
echo ""

# =============================================================================
# PART 3 — Enable and start the service
# =============================================================================
echo "Enabling and starting spectrum-x service..."
sudo systemctl daemon-reload
sudo systemctl enable spectrum-x.service
sudo systemctl start spectrum-x.service

echo ""

# =============================================================================
# PART 4 — Summary
# =============================================================================
echo "=== Installation Complete ==="
echo ""
echo "Files written:"
echo "  /usr/local/sbin/configure-spectrum-x-rhel.sh  — configuration script"
echo "  /etc/systemd/system/spectrum-x.service         — systemd service unit"
echo ""
echo "Interfaces configured:"
for iface in $INTERFACES; do
    echo "  $iface"
done
echo ""
echo "To check service status:  systemctl status spectrum-x.service"
echo "To view logs:             journalctl -u spectrum-x.service"
echo "To re-run manually:       sudo /usr/local/sbin/configure-spectrum-x-rhel.sh"
echo "To run with override:     sudo INTERFACES=\"ens32f0np0 ens33f0np0\" /usr/local/sbin/configure-spectrum-x-rhel.sh"
