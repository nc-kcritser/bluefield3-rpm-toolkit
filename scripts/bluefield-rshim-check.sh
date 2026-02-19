#!/bin/bash
# bluefield-rshim-check.sh
# Check and optionally fix RShim access issues on BlueField-3 cards
# For RHEL/Rocky/Alma Linux

FIX_MODE=false

# Parse arguments
if [ "$1" = "--fix-rshim" ]; then
    FIX_MODE=true
fi

echo "=========================================="
echo "BlueField-3 RShim Check"
echo "Hostname: $(hostname)"
echo "Mode: $([ "$FIX_MODE" = true ] && echo "Check and Fix" || echo "Check Only")"
echo "=========================================="
echo ""

# Check if running as root (only needed for fix mode)
if [ "$FIX_MODE" = true ] && [ "$EUID" -ne 0 ]; then
    echo "ERROR: --fix-rshim requires root privileges"
    exit 1
fi

# Count BlueField cards
CARD_COUNT=$(lspci -nn -d 15b3:a2dc | wc -l)
echo "Detected $CARD_COUNT BlueField-3 card(s)"
echo ""

if [ $CARD_COUNT -eq 0 ]; then
    echo "ERROR: No BlueField-3 cards detected!"
    exit 1
fi

# Start MST
if [ "$FIX_MODE" = true ]; then
    sudo mst start 2>/dev/null
else
    mst start 2>/dev/null
fi

# Check 1: FORCE_MODE in rshim.conf
echo "Check 1: /etc/rshim.conf FORCE_MODE"
echo "--------------------------------------"
FORCE_MODE_ISSUE=false

if [ ! -f /etc/rshim.conf ]; then
    echo "✗ ERROR: /etc/rshim.conf not found!"
    FORCE_MODE_ISSUE=true
elif grep -q "^FORCE_MODE.*1" /etc/rshim.conf; then
    echo "✓ FORCE_MODE is enabled"
else
    echo "✗ FORCE_MODE is disabled or not set"
    FORCE_MODE_ISSUE=true
    
    if [ "$FIX_MODE" = true ]; then
        echo "  Fixing: Enabling FORCE_MODE..."
        
        if grep -q "^#FORCE_MODE" /etc/rshim.conf; then
            sudo sed -i 's/^#FORCE_MODE.*/FORCE_MODE     1/' /etc/rshim.conf
        else
            echo "" | sudo tee -a /etc/rshim.conf > /dev/null
            echo "# Enable force mode for multiple BlueField cards" | sudo tee -a /etc/rshim.conf > /dev/null
            echo "FORCE_MODE     1" | sudo tee -a /etc/rshim.conf > /dev/null
        fi
        
        echo "  ✓ FORCE_MODE enabled in /etc/rshim.conf"
        FORCE_MODE_ISSUE=false
    fi
fi
echo ""

# Check 2: INTERNAL_CPU_RSHIM on all cards
echo "Check 2: INTERNAL_CPU_RSHIM on all cards"
echo "--------------------------------------"
CARDS_NEED_RSHIM_FIX=0
CARDS_WITH_RSHIM=()
CARDS_WITHOUT_RSHIM=()

for i in {0..7}; do
    MST_DEV="/dev/mst/mt41692_pciconf${i}"
    if [ -e "$MST_DEV" ]; then
        RSHIM_STATUS=$(mlxconfig -d $MST_DEV q 2>/dev/null | grep "INTERNAL_CPU_RSHIM" | awk '{print $NF}')
        
        if [ "$RSHIM_STATUS" = "ENABLED(0)" ]; then
            echo "✓ Card $i: INTERNAL_CPU_RSHIM is ENABLED"
            CARDS_WITH_RSHIM+=($i)
        else
            echo "✗ Card $i: INTERNAL_CPU_RSHIM is DISABLED"
            CARDS_WITHOUT_RSHIM+=($i)
            CARDS_NEED_RSHIM_FIX=$((CARDS_NEED_RSHIM_FIX + 1))
        fi
    fi
done
echo ""

# Fix INTERNAL_CPU_RSHIM if needed and in fix mode
if [ $CARDS_NEED_RSHIM_FIX -gt 0 ] && [ "$FIX_MODE" = true ]; then
    echo "Fixing: Enabling INTERNAL_CPU_RSHIM on ${#CARDS_WITHOUT_RSHIM[@]} card(s)..."
    
    for card_num in "${CARDS_WITHOUT_RSHIM[@]}"; do
        MST_DEV="/dev/mst/mt41692_pciconf${card_num}"
        echo "  Configuring card $card_num..."
        sudo mlxconfig -d $MST_DEV set INTERNAL_CPU_RSHIM=0 -y
    done
    
    echo "  ✓ INTERNAL_CPU_RSHIM enabled on all cards"
    echo ""
fi

# Check 3: RShim devices
echo "Check 3: RShim devices"
echo "--------------------------------------"
RSHIM_COUNT=$(ls /dev/rshim* 2>/dev/null | wc -l)

if [ $RSHIM_COUNT -eq 0 ]; then
    echo "✗ No RShim devices found (expected $CARD_COUNT)"
    
    if [ "$FIX_MODE" = true ] && [ "$FORCE_MODE_ISSUE" = false ]; then
        echo "  Fixing: Restarting rshim service..."
        sudo systemctl restart rshim.service
        sleep 3
        
        RSHIM_COUNT=$(ls /dev/rshim* 2>/dev/null | wc -l)
        if [ $RSHIM_COUNT -gt 0 ]; then
            echo "  ✓ RShim service restarted, found $RSHIM_COUNT device(s)"
        else
            echo "  ✗ Still no RShim devices after restart"
        fi
    fi
elif [ $RSHIM_COUNT -eq $CARD_COUNT ]; then
    echo "✓ All $CARD_COUNT RShim devices present"
    ls -1d /dev/rshim* 2>/dev/null | sed 's/^/  /'
else
    echo "⚠ Found $RSHIM_COUNT RShim devices (expected $CARD_COUNT)"
    ls -1d /dev/rshim* 2>/dev/null | sed 's/^/  /'
    
    if [ "$FIX_MODE" = true ]; then
        echo "  Fixing: Restarting rshim service..."
        sudo systemctl restart rshim.service
        sleep 3
        
        RSHIM_COUNT=$(ls /dev/rshim* 2>/dev/null | wc -l)
        echo "  After restart: $RSHIM_COUNT device(s)"
    fi
fi
echo ""

# Check 4: RShim service status
echo "Check 4: RShim service"
echo "--------------------------------------"
RSHIM_ACTIVE=$(systemctl is-active rshim.service 2>/dev/null)
if [ "$RSHIM_ACTIVE" = "active" ]; then
    echo "✓ rshim.service is active"
else
    echo "✗ rshim.service is $RSHIM_ACTIVE"
    
    if [ "$FIX_MODE" = true ]; then
        echo "  Fixing: Starting rshim service..."
        sudo systemctl start rshim.service
        sleep 2
        
        RSHIM_ACTIVE=$(systemctl is-active rshim.service 2>/dev/null)
        if [ "$RSHIM_ACTIVE" = "active" ]; then
            echo "  ✓ rshim.service started"
        else
            echo "  ✗ Failed to start rshim.service"
        fi
    fi
fi
echo ""

# Final Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
ISSUES_FOUND=false
REBOOT_NEEDED=false

# Summary of checks
if [ "$FORCE_MODE_ISSUE" = true ]; then
    echo "✗ FORCE_MODE: Needs configuration"
    ISSUES_FOUND=true
else
    echo "✓ FORCE_MODE: OK"
fi

if [ $CARDS_NEED_RSHIM_FIX -gt 0 ]; then
    if [ "$FIX_MODE" = true ]; then
        echo "⚠ INTERNAL_CPU_RSHIM: Fixed on $CARDS_NEED_RSHIM_FIX card(s) - REBOOT REQUIRED"
        REBOOT_NEEDED=true
    else
        echo "✗ INTERNAL_CPU_RSHIM: $CARDS_NEED_RSHIM_FIX card(s) need configuration"
        ISSUES_FOUND=true
    fi
else
    echo "✓ INTERNAL_CPU_RSHIM: OK on all cards"
fi

RSHIM_COUNT=$(ls /dev/rshim* 2>/dev/null | wc -l)
if [ $RSHIM_COUNT -eq $CARD_COUNT ]; then
    echo "✓ RShim devices: $RSHIM_COUNT/$CARD_COUNT present"
else
    echo "⚠ RShim devices: $RSHIM_COUNT/$CARD_COUNT present"
    if [ "$FIX_MODE" = false ]; then
        ISSUES_FOUND=true
    fi
fi

if [ "$RSHIM_ACTIVE" = "active" ]; then
    echo "✓ RShim service: Running"
else
    echo "✗ RShim service: Not running"
    if [ "$FIX_MODE" = false ]; then
        ISSUES_FOUND=true
    fi
fi

echo ""

# Action recommendations
if [ "$FIX_MODE" = false ] && [ "$ISSUES_FOUND" = true ]; then
    echo "Issues detected. Run with --fix-rshim to automatically fix:"
    echo "  sudo $0 --fix-rshim"
    exit 1
elif [ "$FIX_MODE" = true ] && [ "$REBOOT_NEEDED" = true ]; then
    echo "=========================================="
    echo "⚠ REBOOT REQUIRED"
    echo "=========================================="
    echo "INTERNAL_CPU_RSHIM changes require a reboot to take effect."
    echo ""
    read -p "Reboot now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Rebooting in 5 seconds..."
        sleep 5
        sudo reboot
    else
        echo "Please reboot manually: sudo reboot"
        exit 0
    fi
elif [ "$FIX_MODE" = true ] && [ "$ISSUES_FOUND" = false ]; then
    echo "✓ All RShim issues resolved!"
    exit 0
else
    echo "✓ All RShim checks passed!"
    exit 0
fi
