#!/bin/bash
# bluefield-status.sh
# Comprehensive status check for BlueField-3 SuperNIC cards
# For RHEL/Rocky/Alma Linux

echo "=========================================="
echo "BlueField-3 Card Status Check"
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "=========================================="
echo ""

# Start MST if needed
sudo mst start 2>/dev/null

# Find all BlueField-3 cards
echo "Detecting BlueField-3 cards..."
BLUEFIELD_DEVICES=$(lspci -nn -d 15b3:a2dc | awk '{print $1}')
CARD_COUNT=$(echo "$BLUEFIELD_DEVICES" | grep -c .)

if [ $CARD_COUNT -eq 0 ]; then
    echo "ERROR: No BlueField-3 cards detected!"
    exit 1
fi

echo "Found $CARD_COUNT BlueField-3 card(s)"
echo ""

# Check each card
CARD_NUM=0
for pci_addr in $BLUEFIELD_DEVICES; do
    echo "=========================================="
    echo "Card $CARD_NUM - PCI Address: $pci_addr"
    echo "=========================================="
    
    # Find corresponding interface name
    IFACE=$(ls /sys/bus/pci/devices/0000:${pci_addr}/net/ 2>/dev/null | head -1)
    if [ -n "$IFACE" ]; then
        echo "Interface: $IFACE"
        
        # Get IP address if assigned
        IP_ADDR=$(ip -4 addr show $IFACE 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        if [ -n "$IP_ADDR" ]; then
            echo "IP Address: $IP_ADDR"
        else
            echo "IP Address: Not assigned"
        fi
        
        # Check link status
        LINK_STATE=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null)
        echo "Link State: $LINK_STATE"
    else
        echo "Interface: Not found"
    fi
    
    # Get MST device
    MST_DEV=$(mst status -v 2>/dev/null | grep "$pci_addr" | awk '{print $1}' | head -1)
    if [ -z "$MST_DEV" ]; then
        echo "ERROR: MST device not found for $pci_addr"
        echo ""
        CARD_NUM=$((CARD_NUM + 1))
        continue
    fi
    echo "MST Device: $MST_DEV"
    
    # Get firmware version
    FW_VERSION=$(flint -d $MST_DEV q 2>/dev/null | grep "FW Version" | awk '{print $3}')
    if [ -n "$FW_VERSION" ]; then
        echo "Firmware Version: $FW_VERSION"
    fi
    
    echo ""
    echo "Configuration:"
    echo "--------------"
    
    # Check key configuration parameters
    sudo mlxconfig -d $MST_DEV q 2>/dev/null | grep -E "INTERNAL_CPU_RSHIM|INTERNAL_CPU_MODEL|INTERNAL_CPU_OFFLOAD_ENGINE|ROCE_CONTROL|ROCE_ADAPTIVE_ROUTING_EN|LINK_TYPE_P1|USER_PROGRAMMABLE_CC|TX_SCHEDULER_LOCALITY_MODE" | while read line; do
        echo "  $line"
    done
    
    echo ""
    echo "Spectrum-X RoCE Accelerations:"
    echo "-------------------------------"
    
    # Check Spectrum-X settings using PCI address
    PCI_FULL="0000:$pci_addr"
    ROCE_ACCL=$(sudo mlxreg -d $PCI_FULL --get --reg_name ROCE_ACCL 2>/dev/null | grep -E "roce_tx_window_en|adaptive_routing_forced_en|roce_adp_retrans_en" | grep -v field_select)
    if [ -n "$ROCE_ACCL" ]; then
        echo "$ROCE_ACCL" | while read line; do
            echo "  $line"
        done
    else
        echo "  Could not read ROCE_ACCL register"
    fi
    
    echo ""
    echo "RDMA Device:"
    echo "------------"
    
    # Check for RDMA device
    if [ -n "$IFACE" ] && [ -d "/sys/class/net/$IFACE/device/infiniband" ]; then
        RDMA_DEV=$(ls /sys/class/net/$IFACE/device/infiniband/ 2>/dev/null | head -1)
        if [ -n "$RDMA_DEV" ]; then
            echo "  RDMA Device: $RDMA_DEV"
            
            # Check port state
            PORT_STATE=$(cat /sys/class/infiniband/$RDMA_DEV/ports/1/state 2>/dev/null)
            echo "  Port State: $PORT_STATE"
        else
            echo "  No RDMA device found"
        fi
    else
        echo "  No RDMA device found"
    fi
    
    echo ""
    CARD_NUM=$((CARD_NUM + 1))
done

# Check RShim devices
echo "=========================================="
echo "RShim Status"
echo "=========================================="
echo ""

RSHIM_COUNT=$(ls /dev/rshim* 2>/dev/null | wc -l)
if [ $RSHIM_COUNT -gt 0 ]; then
    echo "Found $RSHIM_COUNT RShim device(s):"
    ls -1d /dev/rshim* 2>/dev/null
    echo ""
    
    # Check RShim service
    echo "RShim Service Status:"
    systemctl is-active rshim.service 2>/dev/null
    
    # Check FORCE_MODE
    if grep -q "^FORCE_MODE.*1" /etc/rshim.conf 2>/dev/null; then
        echo "FORCE_MODE: Enabled ✓"
    else
        echo "FORCE_MODE: Disabled (⚠ may cause issues with multiple cards)"
    fi
else
    echo "WARNING: No RShim devices found!"
    echo "This may indicate:"
    echo "  - INTERNAL_CPU_RSHIM is disabled on cards"
    echo "  - rshim service is not running"
    echo "  - FORCE_MODE is not enabled in /etc/rshim.conf"
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Total BlueField-3 cards: $CARD_COUNT"
echo "RShim devices available: $RSHIM_COUNT"
if [ $CARD_COUNT -eq $RSHIM_COUNT ]; then
    echo "Status: ✓ All cards have RShim access"
else
    echo "Status: ⚠ Mismatch between cards and RShim devices"
    echo "  Run: sudo ./bluefield-rshim-check.sh --fix-rshim"
fi
echo ""
