#!/bin/bash
# bluefield-quick-check.sh
# Quick health check of BlueField-3 cards
# For RHEL/Rocky/Alma Linux

echo "=========================================="
echo "BlueField-3 Quick Health Check"
echo "Hostname: $(hostname)"
echo "=========================================="
echo ""

OVERALL_STATUS="HEALTHY"

# Check 1: BlueField-3 card detection
echo "Check 1: BlueField-3 Card Detection"
echo "------------------------------------"
CARD_COUNT=$(lspci -nn -d 15b3:a2dc | wc -l)
if [ $CARD_COUNT -eq 8 ]; then
    echo "✓ PASS: 8 BlueField-3 cards detected"
elif [ $CARD_COUNT -gt 0 ]; then
    echo "⚠ WARNING: Only $CARD_COUNT card(s) detected (expected 8)"
    OVERALL_STATUS="WARNING"
else
    echo "✗ FAIL: No BlueField-3 cards detected"
    OVERALL_STATUS="FAIL"
fi
echo ""

# Check 2: RShim devices
echo "Check 2: RShim Device Availability"
echo "-----------------------------------"
RSHIM_COUNT=$(ls /dev/rshim* 2>/dev/null | wc -l)
if [ $RSHIM_COUNT -eq 8 ]; then
    echo "✓ PASS: All 8 RShim devices present"
elif [ $RSHIM_COUNT -gt 0 ]; then
    echo "⚠ WARNING: Only $RSHIM_COUNT RShim device(s) present (expected 8)"
    echo "  Fix with: sudo ./bluefield-rshim-check.sh --fix-rshim"
    OVERALL_STATUS="WARNING"
else
    echo "✗ FAIL: No RShim devices found"
    echo "  Fix with: sudo ./bluefield-rshim-check.sh --fix-rshim"
    OVERALL_STATUS="FAIL"
fi
echo ""

# Check 3: RDMA devices
echo "Check 3: RDMA Device Status"
echo "----------------------------"
if command -v ibv_devices >/dev/null 2>&1; then
    RDMA_COUNT=$(ibv_devices 2>/dev/null | grep -c "mlx5")
    if [ $RDMA_COUNT -ge 8 ]; then
        echo "✓ PASS: $RDMA_COUNT RDMA device(s) detected"
    elif [ $RDMA_COUNT -gt 0 ]; then
        echo "⚠ WARNING: Only $RDMA_COUNT RDMA device(s) detected"
        OVERALL_STATUS="WARNING"
    else
        echo "✗ FAIL: No RDMA devices detected"
        OVERALL_STATUS="FAIL"
    fi
else
    echo "⚠ SKIP: ibv_devices command not available"
fi
echo ""

# Check 4: Spectrum-X accelerations (sample first interface)
echo "Check 4: Spectrum-X RoCE Accelerations"
echo "---------------------------------------"
if [ -d "/sys/class/net/ens32f0np0" ]; then
    PCI_ADDR=$(cat /sys/class/net/ens32f0np0/device/uevent 2>/dev/null | grep PCI_SLOT_NAME | cut -d'=' -f 2)
    if [ -n "$PCI_ADDR" ]; then
        TX_WINDOW=$(sudo mlxreg -d $PCI_ADDR --get --reg_name ROCE_ACCL 2>/dev/null | grep "roce_tx_window_en " | grep -v field | awk '{print $NF}')
        ADAPTIVE=$(sudo mlxreg -d $PCI_ADDR --get --reg_name ROCE_ACCL 2>/dev/null | grep "adaptive_routing_forced_en " | grep -v field | awk '{print $NF}')
        
        if [ "$TX_WINDOW" = "0x00000001" ] && [ "$ADAPTIVE" = "0x00000001" ]; then
            echo "✓ PASS: Spectrum-X accelerations enabled"
        else
            echo "⚠ WARNING: Spectrum-X accelerations not enabled"
            echo "  Fix with: sudo systemctl restart spectrum-x-roce.service"
            OVERALL_STATUS="WARNING"
        fi
    else
        echo "⚠ SKIP: Could not read PCI address"
    fi
else
    echo "⚠ SKIP: Test interface not found"
fi
echo ""

# Check 5: Network interface status
echo "Check 5: Network Interface Status"
echo "----------------------------------"
UP_COUNT=0
DOWN_COUNT=0
for iface in ens32f0np0 ens33f0np0 ens34f0np0 ens35f0np0 ens36f0np0 ens37f0np0 ens38f0np0 ens39f0np0; do
    if [ -d "/sys/class/net/$iface" ]; then
        STATE=$(cat /sys/class/net/$iface/operstate 2>/dev/null)
        if [ "$STATE" = "up" ]; then
            UP_COUNT=$((UP_COUNT + 1))
        else
            DOWN_COUNT=$((DOWN_COUNT + 1))
        fi
    fi
done

TOTAL=$((UP_COUNT + DOWN_COUNT))
if [ $UP_COUNT -eq $TOTAL ] && [ $TOTAL -eq 8 ]; then
    echo "✓ PASS: All 8 interfaces UP"
elif [ $UP_COUNT -gt 0 ]; then
    echo "⚠ INFO: $UP_COUNT/$TOTAL interfaces UP, $DOWN_COUNT DOWN"
    echo "  (Some cables may be unplugged - this is normal)"
else
    echo "✗ FAIL: No interfaces UP"
    OVERALL_STATUS="FAIL"
fi
echo ""

# Check 6: Spectrum-X service
echo "Check 6: Spectrum-X Service Status"
echo "-----------------------------------"
if systemctl is-enabled spectrum-x-roce.service >/dev/null 2>&1; then
    if systemctl is-active spectrum-x-roce.service >/dev/null 2>&1; then
        echo "✓ PASS: spectrum-x-roce.service enabled and running"
    else
        echo "⚠ WARNING: spectrum-x-roce.service enabled but not running"
        echo "  Fix with: sudo systemctl start spectrum-x-roce.service"
        OVERALL_STATUS="WARNING"
    fi
else
    echo "⚠ WARNING: spectrum-x-roce.service not installed"
    echo "  Install with: sudo ./setup-spectrum-x-rhel.sh"
    OVERALL_STATUS="WARNING"
fi
echo ""

# Overall Summary
echo "=========================================="
echo "Overall Status: $OVERALL_STATUS"
echo "=========================================="

if [ "$OVERALL_STATUS" = "HEALTHY" ]; then
    echo "✓ All checks passed!"
    exit 0
elif [ "$OVERALL_STATUS" = "WARNING" ]; then
    echo "⚠ Some checks need attention (see above)"
    exit 1
else
    echo "✗ Critical issues detected (see above)"
    exit 2
fi
