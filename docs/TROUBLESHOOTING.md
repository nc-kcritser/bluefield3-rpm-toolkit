# Troubleshooting Guide

Common issues and solutions for BlueField-3 SuperNIC deployment.

## Table of Contents

1. [RShim Issues](#rshim-issues)
2. [Network Configuration Issues](#network-configuration-issues)
3. [Spectrum-X Acceleration Issues](#spectrum-x-acceleration-issues)
4. [Firmware Update Issues](#firmware-update-issues)
5. [Performance Issues](#performance-issues)
6. [Hardware Issues](#hardware-issues)

---

## RShim Issues

### Only 3-5 RShim devices appear instead of 8

**Symptoms:**
```bash
$ ls /dev/rshim*
/dev/rshim0  /dev/rshim1  /dev/rshim2
# Missing rshim3 through rshim7
```

**Cause:** FORCE_MODE not enabled in /etc/rshim.conf

**Solution:**
```bash
# Quick fix
sudo ./scripts/bluefield-rshim-check.sh --fix-rshim

# Manual fix
sudo nano /etc/rshim.conf
# Add or uncomment:
FORCE_MODE     1

sudo systemctl restart rshim.service
```

**Verification:**
```bash
ls /dev/rshim*  # Should show rshim0 through rshim7
```

---

### RShim service fails to start

**Symptoms:**
```bash
$ systemctl status rshim.service
● rshim.service - rshim driver for BlueField SoC
   Loaded: loaded
   Active: failed
```

**Diagnostic:**
```bash
sudo journalctl -u rshim.service -n 50
```

**Common causes and solutions:**

1. **Missing kernel module:**
   ```bash
   # Check if rshim module is loaded
   lsmod | grep rshim
   
   # Load manually if needed
   sudo modprobe rshim
   ```

2. **Permission issues:**
   ```bash
   # Check rshim device permissions
   ls -la /dev/rshim*
   
   # Should be owned by root or rshim group
   ```

3. **Conflicting drivers:**
   ```bash
   # Check for conflicts
   sudo dmesg | grep rshim
   ```

---

### INTERNAL_CPU_RSHIM disabled on cards

**Symptoms:**
```bash
$ sudo mlxconfig -d /dev/mst/mt41692_pciconf0 q | grep INTERNAL_CPU_RSHIM
INTERNAL_CPU_RSHIM                          DISABLED(1)
```

**Solution:**
```bash
# Use the fix script
sudo ./scripts/bluefield-rshim-check.sh --fix-rshim

# Or manually
sudo mlxconfig -d /dev/mst/mt41692_pciconf0 set INTERNAL_CPU_RSHIM=0 -y
# Repeat for all cards (pciconf0 through pciconf7)

# Reboot required
sudo reboot
```

---

## Network Configuration Issues

### Interfaces not getting IPs

**Symptoms:**
```bash
$ ip addr show ens32f0np0
# No inet address shown
```

**Diagnostic:**
```bash
# Check NetworkManager connections
nmcli con show

# Check if interface is managed
nmcli device status | grep ens32f0np0
```

**Solutions:**

1. **Interface unmanaged by NetworkManager:**
   ```bash
   # Edit NetworkManager config
   sudo nano /etc/NetworkManager/NetworkManager.conf
   
   # Ensure [main] section has:
   [main]
   plugins=ifcfg-rh
   
   # Restart NetworkManager
   sudo systemctl restart NetworkManager
   ```

2. **Connection failed to apply:**
   ```bash
   # Check connection status
   nmcli con show rail1
   
   # Manually bring up
   sudo nmcli con up rail1
   
   # Check logs
   sudo journalctl -xe | grep NetworkManager
   ```

3. **Reconfigure interface:**
   ```bash
   # Delete and recreate
   sudo nmcli con delete rail1
   sudo ./scripts/bluefield-configure-ips.sh 4  # your host ID
   ```

---

### Routing table issues

**Symptoms:**
- Can't ping gateway on specific rail
- Traffic going out wrong interface

**Diagnostic:**
```bash
# Check routing tables
ip route show table 101  # Rail 1
ip route show table 102  # Rail 2
# etc...

# Check routing rules
ip rule show | grep 192.168
```

**Solution:**
```bash
# Reconfigure network
sudo ./scripts/bluefield-configure-ips.sh 4
```

---

### MTU mismatch

**Symptoms:**
- Connection works but performance is poor
- Large packets dropped

**Diagnostic:**
```bash
# Check MTU on interface
ip link show ens32f0np0 | grep mtu

# Should show: mtu 9216
```

**Solution:**
```bash
# Fix single interface
sudo nmcli con mod rail1 802-3-ethernet.mtu 9216
sudo nmcli con up rail1

# Or reconfigure all
sudo ./scripts/bluefield-configure-ips.sh 4
```

---

## Spectrum-X Acceleration Issues

### Accelerations not enabled after reboot

**Symptoms:**
```bash
$ sudo mlxreg -d 0000:17:00.0 --get --reg_name ROCE_ACCL | grep roce_tx_window_en
roce_tx_window_en                              | 0x00000000
# Should be 0x00000001
```

**Cause:** Spectrum-X settings don't persist across reboots (by design)

**Solution:**
```bash
# Install the systemd service (if not already done)
sudo ./scripts/setup-spectrum-x-rhel.sh

# Or manually restart service
sudo systemctl restart spectrum-x-roce.service

# Verify
./scripts/bluefield-status.sh | grep -A3 "Spectrum-X"
```

---

### Spectrum-X service fails

**Symptoms:**
```bash
$ systemctl status spectrum-x-roce.service
● spectrum-x-roce.service - Configure Spectrum-X
   Active: failed
```

**Diagnostic:**
```bash
sudo journalctl -u spectrum-x-roce.service -n 50
```

**Common issues:**

1. **mlxreg command not found:**
   ```bash
   # Install DOCA or MLNX OFED
   sudo dnf install doca-host
   ```

2. **Interface names mismatch:**
   ```bash
   # Edit the service script
   sudo nano /usr/local/bin/configure-spectrum-x-rhel.sh
   
   # Update INTERFACES variable to match your system
   ```

3. **Permission issues:**
   ```bash
   # Check script permissions
   ls -la /usr/local/bin/configure-spectrum-x-rhel.sh
   # Should be: -rwxr-xr-x root root
   
   sudo chmod +x /usr/local/bin/configure-spectrum-x-rhel.sh
   ```

---

## Firmware Update Issues

### Firmware update fails on some cards

**Symptoms:**
```bash
$ sudo bfb-install --bfb firmware.bfb --rshim rshim3
Error: Cannot access rshim3
```

**Solution:**
```bash
# Ensure all rshim devices are accessible
sudo ./scripts/bluefield-rshim-check.sh --fix-rshim

# Verify before updating
ls /dev/rshim*  # Should show all 8 devices

# Retry firmware update
```

---

### Firmware update hangs

**Symptoms:**
- bfb-install command runs but never completes
- Card appears unresponsive

**Diagnostic:**
```bash
# Check rshim console
sudo cat /dev/rshimX/console  # where X is the card number

# Check rshim misc
sudo cat /dev/rshimX/misc
```

**Solution:**
```bash
# Cancel the update
Ctrl+C

# Reset the rshim device
sudo systemctl restart rshim.service

# Wait 30 seconds, then retry

# If still hangs, may need host reboot
```

---

### Cards don't boot after firmware update

**Symptoms:**
- Cards present in lspci but not functional
- No network interfaces appear

**Diagnostic:**
```bash
# Check if cards are detected
lspci -nn | grep 15b3:a2dc

# Check boot status via rshim
sudo cat /dev/rshim0/misc
```

**Solution:**
```bash
# Reset cards
for i in {0..7}; do
    echo "SW_RESET 1" | sudo tee /dev/rshim${i}/misc
    sleep 2
    echo "SW_RESET 0" | sudo tee /dev/rshim${i}/misc
done

# If that doesn't work, cold boot
sudo reboot
```

---

## Performance Issues

### Low bandwidth on RoCE connections

**Diagnostic:**
```bash
# Check Spectrum-X accelerations
./scripts/bluefield-status.sh | grep -A3 "Spectrum-X"

# Check MTU
ip link show | grep mtu

# Check for errors
ip -s link show ens32f0np0

# Check RoCE parameters
sudo mlxconfig -d /dev/mst/mt41692_pciconf0 q | grep ROCE
```

**Solutions:**

1. **Enable Spectrum-X accelerations:**
   ```bash
   sudo systemctl restart spectrum-x-roce.service
   ```

2. **Verify MTU is 9216:**
   ```bash
   sudo ./scripts/bluefield-configure-ips.sh 4
   ```

3. **Check congestion control:**
   ```bash
   # Should be enabled via Spectrum-X script
   ls /sys/class/net/ens32f0np0/ecn/roce_rp/enable/
   ```

---

### High latency

**Common causes:**

1. **CPU frequency scaling:**
   ```bash
   # Set to performance mode
   sudo cpupower frequency-set -g performance
   ```

2. **IRQ affinity not optimized:**
   ```bash
   # Check current IRQ affinity
   cat /proc/interrupts | grep mlx5
   
   # May need to tune IRQ affinity for your workload
   ```

3. **NUMA issues:**
   ```bash
   # Check NUMA topology
   numactl --hardware
   
   # Ensure processes run on same NUMA node as NIC
   ```

---

## Hardware Issues

### Card not detected by PCIe

**Symptoms:**
```bash
$ lspci -nn | grep 15b3:a2dc
# No output or missing cards
```

**Diagnostic:**
```bash
# Check PCIe tree
lspci -tv | grep Mellanox

# Check dmesg for PCIe errors
sudo dmesg | grep -i pcie | grep -i error

# Check BIOS PCIe settings
```

**Solutions:**

1. **Reseat the card:**
   - Power off system
   - Remove and reinsert card
   - Ensure fully seated

2. **Check BIOS settings:**
   - PCIe should be enabled
   - IOMMU/VT-d settings
   - Above 4G decoding enabled
   - SR-IOV enabled (if using)

3. **Try different PCIe slot:**
   - Ensure slot is Gen4 or Gen5 x16

---

### Card thermal throttling

**Symptoms:**
- Performance degrades over time
- Card runs very hot

**Diagnostic:**
```bash
# Check temperature (if available via BMC or sensors)
sudo sensors | grep -i temp

# Check for throttling messages
sudo dmesg | grep -i thermal
```

**Solutions:**

1. **Improve airflow:**
   - Verify server fans are working
   - Ensure no airflow obstructions
   - Check ambient temperature

2. **Check thermal paste:**
   - May need to be reapplied (RMA if under warranty)

3. **Reduce workload temporarily:**
   - Allow cards to cool
   - Verify cooling before continuing

---

### Link not coming up

**Symptoms:**
```bash
$ ip link show ens32f0np0
# state DOWN
```

**Diagnostic:**
```bash
# Check physical link
sudo ethtool ens32f0np0 | grep "Link detected"

# Check cable
# Check switch port

# Check for port errors
ip -s link show ens32f0np0
```

**Solutions:**

1. **Cable issues:**
   - Verify cable is properly seated
   - Try different cable
   - Check cable type (AOC vs DAC)

2. **Switch configuration:**
   - Verify switch port is enabled
   - Check VLAN configuration
   - Verify speed/duplex settings

3. **Force link up:**
   ```bash
   sudo ip link set ens32f0np0 up
   sudo nmcli con up rail1
   ```

---

## Getting More Help

If issues persist after trying these solutions:

1. **Collect diagnostic information:**
   ```bash
   ./scripts/bluefield-status.sh > diagnostic.txt
   ./scripts/bluefield-quick-check.sh >> diagnostic.txt
   sudo journalctl -u rshim.service >> diagnostic.txt
   sudo journalctl -u spectrum-x-roce.service >> diagnostic.txt
   sudo dmesg >> diagnostic.txt
   ```

2. **Check NVIDIA documentation:**
   - BlueField-3 User Guide
   - DOCA documentation
   - Release notes for your firmware version

3. **Contact support:**
   - Include diagnostic.txt
   - Firmware version
   - OS version
   - Hardware details

---

## Preventive Maintenance

### Regular checks (weekly)

```bash
# Quick health check
./scripts/bluefield-quick-check.sh

# Check for errors
sudo dmesg | grep -i error | tail -20
```

### Monthly audit

```bash
# Full status report
./scripts/bluefield-status.sh > monthly-report-$(date +%Y%m%d).txt

# Check firmware versions
# Plan updates if needed
```

### Before major changes

```bash
# Backup current configuration
nmcli con show > network-config-backup.txt
ip addr > ip-config-backup.txt
ip route show table all > routing-backup.txt

# Run full diagnostic
./scripts/bluefield-status.sh > pre-change-status.txt
```
