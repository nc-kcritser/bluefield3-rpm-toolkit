#!/bin/bash
# bluefield-configure-ips.sh
# Spectrum-X 8-Rail Configuration for BlueField-3 SuperNICs
# For RHEL/Rocky/Alma Linux
#
# This script configures BlueField interfaces with:
# - Static IPs on isolated rails
# - Custom routing tables per rail
# - Policy-based routing for traffic isolation
# - MTU 9216 for high-performance networking
#
# Usage: ./bluefield-configure-ips.sh <HOST_ID> [--dry-run]
# Example: ./bluefield-configure-ips.sh 4
#          ./bluefield-configure-ips.sh 4 --dry-run

# =============================================================================
# CONFIGURATION - Edit these values for your environment
# =============================================================================

# Base IP network (first 2 octets)
# Example: "192.168" creates 192.168.x.x networks
#          "10.100" creates 10.100.x.x networks
#          "172.16" creates 172.16.x.x networks
BASE_IP="192.168"

# Gateway last octet (usually .254 or .1)
# The gateway for each rail will be: <BASE_IP>.<RAIL_NUM>.<GATEWAY_OCTET>
# Example: For rail 1 with BASE_IP="192.168" and GATEWAY_OCTET="254"
#          Gateway becomes: 192.168.1.254
GATEWAY_OCTET="254"

# MTU size (9216 recommended for high-performance networking)
MTU=9216

# Network mask bits (usually 24 for /24 networks)
NETMASK_BITS=24

# Base routing table ID (each rail gets BASE_TABLE_ID + RAIL_NUM)
# Example: Rail 1 = table 101, Rail 2 = table 102, etc.
BASE_TABLE_ID=100

# Limiter route (prevents rails from being used for management/internet traffic)
# Set to match your data center network range
# Example: "192.168.0.0/20" covers 192.168.0.0 through 192.168.15.255
LIMITER_ROUTE="192.168.0.0/20"

# Interface mapping - Update if your interface names differ
# Mapped sequentially to Rails 1 through 8
IFACES=(
    "ens32f0np0" # Rail 1 -> Leaf 1 (VLAN 1)
    "ens33f0np0" # Rail 2 -> Leaf 1 (VLAN 2)
    "ens34f0np0" # Rail 3 -> Leaf 1 (VLAN 3)
    "ens35f0np0" # Rail 4 -> Leaf 1 (VLAN 4)
    "ens36f0np0" # Rail 5 -> Leaf 2 (VLAN 5)
    "ens37f0np0" # Rail 6 -> Leaf 2 (VLAN 6)
    "ens38f0np0" # Rail 7 -> Leaf 2 (VLAN 7)
    "ens39f0np0" # Rail 8 -> Leaf 2 (VLAN 8)
)

# =============================================================================
# END CONFIGURATION - Do not edit below this line unless you know what you're doing
# =============================================================================

# Parse arguments
if [ -z "$1" ]; then
    echo "Usage: $0 <HOST_ID> [--dry-run]"
    echo ""
    echo "Arguments:"
    echo "  HOST_ID    Host identifier (1-254) - becomes last octet of IP"
    echo "  --dry-run  Show what would be configured without making changes"
    echo ""
    echo "Current Configuration:"
    echo "  Base IP:      ${BASE_IP}.x.x"
    echo "  Gateway:      ${BASE_IP}.x.${GATEWAY_OCTET}"
    echo "  Network Mask: /${NETMASK_BITS}"
    echo "  MTU:          ${MTU}"
    echo ""
    echo "Example:"
    echo "  $0 4        # Configure host as ${BASE_IP}.x.4"
    echo "  $0 4 --dry-run  # Preview configuration"
    echo ""
    echo "To change network settings, edit the configuration section at the top of this script."
    exit 1
fi

HOST_ID=$1
DRY_RUN=false

if [ "$2" = "--dry-run" ]; then
    DRY_RUN=true
    echo "=========================================="
    echo "DRY RUN MODE - No changes will be made"
    echo "=========================================="
    echo ""
fi

# Validate HOST_ID
if ! [[ "$HOST_ID" =~ ^[0-9]+$ ]] || [ "$HOST_ID" -lt 1 ] || [ "$HOST_ID" -gt 254 ]; then
    echo "ERROR: HOST_ID must be a number between 1 and 254"
    exit 1
fi

# Validate BASE_IP format (simple check)
if ! [[ "$BASE_IP" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: BASE_IP must be in format 'X.Y' (e.g., '192.168' or '10.100')"
    exit 1
fi

# Check for root
if [ "$DRY_RUN" = false ] && [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check for NetworkManager
if ! systemctl is-active NetworkManager >/dev/null 2>&1; then
    echo "ERROR: NetworkManager is not running"
    echo "Start it with: sudo systemctl start NetworkManager"
    exit 1
fi

echo "=========================================="
echo "Spectrum-X 8-Rail Configuration"
echo "=========================================="
echo "Hostname:     $(hostname)"
echo "Host ID:      $HOST_ID"
echo "Base IP:      ${BASE_IP}.x.x/${NETMASK_BITS}"
echo "Gateway:      ${BASE_IP}.x.${GATEWAY_OCTET}"
echo "MTU:          $MTU"
echo "Mode:         $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "APPLY")"
echo "=========================================="
echo ""

# Verify Interfaces Exist
echo "Verifying interfaces..."
MISSING_IFACES=()
for iface in "${IFACES[@]}"; do
    if [ ! -d "/sys/class/net/$iface" ]; then
        MISSING_IFACES+=("$iface")
    fi
done

if [ ${#MISSING_IFACES[@]} -gt 0 ]; then
    echo "WARNING: The following interfaces were not found:"
    for iface in "${MISSING_IFACES[@]}"; do
        echo "  - $iface"
    done
    echo ""
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi
echo ""

# Configure Each Rail
echo "Configuring GPU Rails for Host .${HOST_ID}..."
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

for i in "${!IFACES[@]}"; do
    RAIL_NUM=$((i+1))
    IFACE="${IFACES[$i]}"
    
    # Skip if interface doesn't exist
    if [ ! -d "/sys/class/net/$IFACE" ]; then
        echo "  [Rail $RAIL_NUM] $IFACE - SKIPPED (interface not found)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi
    
    # IP Scheme: <BASE_IP>.<RAIL>.<HOST_ID>/<NETMASK>
    IP_ADDR="${BASE_IP}.${RAIL_NUM}.${HOST_ID}/${NETMASK_BITS}"
    
    # Gateway Scheme: <BASE_IP>.<RAIL>.<GATEWAY_OCTET>
    GATEWAY="${BASE_IP}.${RAIL_NUM}.${GATEWAY_OCTET}"
    
    # Custom Route Table ID
    TABLE_ID=$((BASE_TABLE_ID + RAIL_NUM))
    CON_NAME="rail${RAIL_NUM}"

    echo "  [Rail $RAIL_NUM] $IFACE"
    echo "    IP:      $IP_ADDR"
    echo "    Gateway: $GATEWAY"
    echo "    Table:   $TABLE_ID"
    
    if [ "$DRY_RUN" = true ]; then
        echo "    Status:  Would be configured"
        echo ""
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        continue
    fi

    # 1. Clean old connection
    nmcli con delete "$CON_NAME" 2>/dev/null

    # 2. Create Connection
    if ! nmcli con add type ethernet con-name "$CON_NAME" ifname "$IFACE" \
        ipv4.method manual \
        ipv4.address "$IP_ADDR" \
        mtu "$MTU" >/dev/null 2>&1; then
        echo "    Status:  FAILED to create connection"
        echo ""
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # 3. Assign to Custom Route Table (Isolation)
    nmcli con mod "$CON_NAME" ipv4.route-table "$TABLE_ID"

    # 4. Add "Limiter" Route
    # This prevents internet/mgmt traffic from accidentally using the rails
    nmcli con mod "$CON_NAME" +ipv4.routes "$LIMITER_ROUTE $GATEWAY table=$TABLE_ID"

    # 5. Add Policy Rule (Source-Based Routing)
    # Ensures return traffic leaves the correct interface
    nmcli con mod "$CON_NAME" +ipv4.routing-rules "priority 100 from ${BASE_IP}.${RAIL_NUM}.${HOST_ID} table $TABLE_ID"

    # 6. Final Settings
    nmcli con mod "$CON_NAME" ipv4.never-default yes
    
    # 7. Bring up interface
    if nmcli con up "$CON_NAME" >/dev/null 2>&1; then
        echo "    Status:  ✓ Configured successfully"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "    Status:  ✗ Failed to bring up"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    echo ""
done

# Summary
echo "=========================================="
echo "Configuration Summary"
echo "=========================================="
echo "Total interfaces: ${#IFACES[@]}"
echo "Configured:       $SUCCESS_COUNT"
echo "Failed:           $FAIL_COUNT"
echo "Skipped:          $SKIP_COUNT"
echo ""

if [ "$DRY_RUN" = false ]; then
    if [ $SUCCESS_COUNT -eq ${#IFACES[@]} ]; then
        echo "✓ All interfaces configured successfully!"
    elif [ $SUCCESS_COUNT -gt 0 ]; then
        echo "⚠ Partial success - some interfaces failed"
    else
        echo "✗ Configuration failed"
        exit 1
    fi
    
    echo ""
    echo "Verification Commands:"
    echo "----------------------"
    echo "View connections:  nmcli con show"
    echo "View IP addresses: ip addr show | grep '${BASE_IP}'"
    echo "View routes:       ip route show table $((BASE_TABLE_ID + 1))"
    echo "View rules:        ip rule show | grep '${BASE_IP}'"
    echo "Test rail 1:       ping -I rail1 ${BASE_IP}.1.${GATEWAY_OCTET}"
else
    echo "Dry run complete. Run without --dry-run to apply changes."
fi

echo ""
echo "=========================================="
echo "Configuration Complete"
echo "=========================================="
