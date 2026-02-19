# Quick Start Guide

Get your BlueField-3 SuperNICs up and running in 15 minutes.

## Prerequisites Check

Before starting, verify you have:

```bash
# Check OS (should be RHEL/Rocky 8 or 9)
cat /etc/redhat-release

# Check for MST tools
which mst mlxconfig mlxreg

# Check for rshim
which bfb-install
systemctl status rshim.service

# Check NetworkManager
systemctl status NetworkManager

# Check for cards
lspci -nn | grep 15b3:a2dc
# Should show 8 BlueField-3 cards
```

If any are missing, see [INSTALL.md](INSTALL.md) for installation instructions.

---

## Step 1: Install the Toolkit (2 minutes)

```bash
# Extract toolkit
cd /opt
sudo tar -xzf bluefield-toolkit.tar.gz
cd bluefield-toolkit

# Make scripts executable
sudo chmod +x scripts/*.sh
```

---

## Step 2: Initial Status Check (1 minute)

```bash
# Run status check
./scripts/bluefield-status.sh

# Look for:
# - 8 cards detected ✓
# - Firmware versions listed ✓
# - SuperNIC mode (INTERNAL_CPU_OFFLOAD_ENGINE = DISABLED) ✓
```

**Sample output:**
```
Found 8 BlueField-3 card(s)
Card 0 - PCI Address: 17:00.0
Interface: ens32f0np0
Firmware Version: 32.41.1000
Configuration:
  INTERNAL_CPU_OFFLOAD_ENGINE          DISABLED(1)
  INTERNAL_CPU_RSHIM                   ENABLED(0)
  ROCE_CONTROL                         ROCE_ENABLE(2)
```

---

## Step 3: Fix RShim Access (2 minutes)

```bash
# Check RShim status
sudo ./scripts/bluefield-rshim-check.sh

# If issues found, fix them
sudo ./scripts/bluefield-rshim-check.sh --fix-rshim

# May require reboot if INTERNAL_CPU_RSHIM was changed
```

**Expected result:**
```
✓ FORCE_MODE: OK
✓ INTERNAL_CPU_RSHIM: OK on all cards
✓ RShim devices: 8/8 present
✓ RShim service: Running
```

---

## Step 4: Configure Spectrum-X Accelerations (3 minutes)

```bash
# Install Spectrum-X service
sudo ./scripts/setup-spectrum-x-rhel.sh

# Verify accelerations are enabled
./scripts/bluefield-status.sh | grep -A3 "Spectrum-X"
```

**Expected result:**
```
Spectrum-X RoCE Accelerations:
  roce_tx_window_en                     | 0x00000001
  adaptive_routing_forced_en            | 0x00000001
  roce_adp_retrans_en                   | 0x00000001
```

---

## Step 5: Configure Network IPs (5 minutes)

### 5a. Customize IP Settings (if needed)

```bash
# Edit configuration section
sudo nano scripts/bluefield-configure-ips.sh

# Key settings:
BASE_IP="192.168"           # Change if using different network
GATEWAY_OCTET="254"         # Usually .254 or .1
MTU=9216                    # High-performance MTU
```

### 5b. Preview Configuration

```bash
# Dry run (preview without applying)
./scripts/bluefield-configure-ips.sh 4 --dry-run

# Replace '4' with your host ID
# This becomes the last octet: 192.168.x.4
```

### 5c. Apply Configuration

```bash
# Apply network configuration
sudo ./scripts/bluefield-configure-ips.sh 4

# Replace '4' with your actual host ID
```

**Expected result:**
```
✓ All interfaces configured successfully!
Configured: 8
Failed: 0
Skipped: 0
```

---

## Step 6: Verify Everything (2 minutes)

```bash
# Quick health check
./scripts/bluefield-quick-check.sh
```

**Expected result:**
```
✓ PASS: 8 BlueField-3 cards detected
✓ PASS: All 8 RShim devices present
✓ PASS: 8+ RDMA device(s) detected
✓ PASS: Spectrum-X accelerations enabled
⚠ INFO: 7/8 interfaces UP (some cables may be unplugged - normal)
✓ PASS: spectrum-x-roce.service enabled and running

Overall Status: HEALTHY
```

---

## Step 7: Test Connectivity (optional)

```bash
# View configured IPs
ip addr show | grep 192.168

# Test ping to gateway on each rail
for i in {1..8}; do
    echo "Testing rail $i..."
    ping -I rail${i} -c 3 192.168.${i}.254
done

# Check routing tables
ip route show table 101  # Rail 1
ip rule show | grep 192.168  # Policy routing
```

---

## You're Done! 🎉

Your BlueField-3 SuperNICs are now configured and ready for production.

### What You've Accomplished:

✅ All 8 BlueField-3 cards detected and configured  
✅ RShim access enabled for firmware updates  
✅ Spectrum-X RoCE accelerations enabled (auto-apply on boot)  
✅ 8-rail network with isolated routing configured  
✅ MTU 9216 for high performance  
✅ Policy-based routing for traffic isolation  

---

## Next Steps

### Regular Maintenance

```bash
# Weekly quick check
./scripts/bluefield-quick-check.sh

# Monthly detailed report
./scripts/bluefield-status.sh > monthly-report-$(date +%Y%m%d).txt
```

### Before Firmware Updates

```bash
# Ensure RShim access
sudo ./scripts/bluefield-rshim-check.sh

# Backup configuration
nmcli con show > network-backup.txt
```

### After Firmware Updates

```bash
# Verify everything still works
./scripts/bluefield-quick-check.sh

# Spectrum-X service should auto-reapply settings
# If not:
sudo systemctl restart spectrum-x-roce.service
```

---

## Common Tasks

### Change Host IP

```bash
# Just run with new host ID
sudo ./scripts/bluefield-configure-ips.sh 5  # new host ID
```

### Check Specific Card

```bash
# View detailed info for one card
./scripts/bluefield-status.sh | grep -A30 "Card 0"
```

### Disable/Enable Interface

```bash
# Disable
sudo nmcli con down rail1

# Enable
sudo nmcli con up rail1
```

### View Logs

```bash
# Spectrum-X service
sudo journalctl -u spectrum-x-roce.service

# RShim service
sudo journalctl -u rshim.service

# NetworkManager
sudo journalctl -u NetworkManager | tail -50
```

---

## Troubleshooting

If something goes wrong, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for detailed solutions.

**Quick fixes:**

```bash
# RShim issues
sudo ./scripts/bluefield-rshim-check.sh --fix-rshim

# Network issues
sudo ./scripts/bluefield-configure-ips.sh 4

# Spectrum-X issues
sudo systemctl restart spectrum-x-roce.service

# Full diagnostic
./scripts/bluefield-status.sh > diagnostic.txt
```

---

## Getting Help

1. Check [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
2. Review script output and logs
3. Run full diagnostic: `./scripts/bluefield-status.sh`
4. Check NVIDIA BlueField documentation

---

## Useful Commands Reference

```bash
# Card Detection
lspci -nn | grep 15b3:a2dc

# RShim Devices
ls /dev/rshim*

# Network Interfaces
ip link show | grep ens

# RDMA Devices
ibv_devices
ibv_devinfo

# Routing
ip route show table all
ip rule show

# Connections
nmcli con show
nmcli device status

# Service Status
systemctl status spectrum-x-roce.service
systemctl status rshim.service
systemctl status NetworkManager
```

---

**Congratulations! Your BlueField-3 deployment is complete!** 🚀
