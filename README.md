# BlueField-3 SuperNIC Management Toolkit

A comprehensive toolkit for managing NVIDIA BlueField-3 SuperNICs on RHEL/Rocky/Alma Linux distributions.

## Overview

This toolkit provides scripts and utilities to:
- ✅ Check BlueField-3 card status and configuration
- ✅ Manage RShim access for firmware updates
- ✅ Configure Spectrum-X RoCE accelerations
- ✅ Set up network interfaces and IP addresses (8-rail configuration)
- ✅ Verify and troubleshoot common issues

## Hardware Support

- **Cards**: NVIDIA BlueField-3 B3140H E-series SuperNICs
- **Mode**: SuperNIC mode (400GbE, ARM cores inactive)
- **OS**: RHEL 8/9, Rocky Linux 8/9, Alma Linux 8/9
- **Configuration**: 8-card deployment with Spectrum-X fabric

## Quick Start

```bash
# 1. Download and extract the toolkit
cd /opt
sudo tar -xzf bluefield-toolkit.tar.gz
cd bluefield-toolkit

# 2. Make scripts executable
chmod +x scripts/*.sh

# 3. Check your BlueField cards
./scripts/bluefield-status.sh

# 4. Fix any RShim issues (if needed)
sudo ./scripts/bluefield-rshim-check.sh --fix-rshim

# 5. Set up Spectrum-X accelerations
sudo ./scripts/setup-spectrum-x-rhel.sh

# 6. Configure network IPs (edit BASE_IP in script first if needed)
sudo ./scripts/bluefield-configure-ips.sh 4  # where 4 is your host ID
```

## Scripts

### 📊 bluefield-status.sh
**Purpose**: Comprehensive status check of all BlueField cards  
**Usage**: `./scripts/bluefield-status.sh`  
**No root required**

**Output includes**:
- Card enumeration and PCI addresses
- Firmware versions
- Configuration parameters (RoCE, mode, RSHIM)
- Network interface status and IPs
- RDMA device status
- Spectrum-X acceleration status
- RShim device availability

**When to use**: 
- Initial deployment verification
- After firmware updates
- Troubleshooting connectivity issues
- Generating diagnostic reports

---

### 🔧 bluefield-rshim-check.sh
**Purpose**: Check and fix RShim access issues  
**Usage**: 
- **Check only**: `./scripts/bluefield-rshim-check.sh`
- **Check and fix**: `sudo ./scripts/bluefield-rshim-check.sh --fix-rshim`

**Checks performed**:
1. FORCE_MODE in /etc/rshim.conf
2. INTERNAL_CPU_RSHIM on all cards
3. RShim device availability (/dev/rshim0-7)
4. RShim service status

**Fixes applied** (with --fix-rshim):
- Enables FORCE_MODE in /etc/rshim.conf
- Enables INTERNAL_CPU_RSHIM on cards where disabled
- Restarts rshim service
- Prompts for reboot if firmware changes needed

**When to use**:
- Before firmware updates (ensure all 8 rshim devices accessible)
- After card replacement
- When firmware update fails on some cards

---

### 🚀 setup-spectrum-x-rhel.sh
**Purpose**: Configure Spectrum-X RoCE accelerations to persist across reboots  
**Usage**: `sudo ./scripts/setup-spectrum-x-rhel.sh`

**Actions performed**:
1. Creates `/usr/local/bin/configure-spectrum-x-rhel.sh`
2. Creates systemd service `spectrum-x-roce.service`
3. Enables service to run at boot
4. Applies Spectrum-X accelerations immediately
5. Verifies configuration

**Features enabled**:
- `roce_tx_window_en` - TX window optimization
- `adaptive_routing_forced_en` - Forced adaptive routing
- `roce_adp_retrans_en` - Adaptive retransmission

**When to use**:
- Initial deployment
- After firmware updates (settings don't persist)
- When RoCE performance is suboptimal

---

### 🌐 bluefield-configure-ips.sh
**Purpose**: Configure IP addresses on BlueField interfaces (8-rail Spectrum-X configuration)  
**Usage**: 
- **Preview**: `./scripts/bluefield-configure-ips.sh 4 --dry-run`
- **Apply**: `sudo ./scripts/bluefield-configure-ips.sh 4`

**Configuration** (edit at top of script):
```bash
BASE_IP="192.168"           # Change to "10.100" or "172.16" as needed
GATEWAY_OCTET="254"         # Usually .254 or .1
MTU=9216                    # High-performance MTU
NETMASK_BITS=24            # /24 subnet
LIMITER_ROUTE="192.168.0.0/20"  # Prevents rails from internet routing
```

**Features**:
- 8-rail configuration with isolated routing tables
- Policy-based routing (source-based)
- MTU 9216 for high-performance
- NetworkManager-based (persistent across reboots)

**When to use**:
- Initial network setup
- Changing host ID
- Migrating to different IP range

---

### ⚡ bluefield-quick-check.sh
**Purpose**: Quick health check of all BlueField cards  
**Usage**: `./scripts/bluefield-quick-check.sh`  
**No root required**

**Quick checks**:
- Card detection (expect 8)
- RShim devices (expect 8)
- RDMA devices (expect 8+)
- Spectrum-X accelerations enabled
- Network interfaces up

**Output**: Simple PASS/FAIL/WARNING status per check

**When to use**:
- Quick validation after changes
- Pre-deployment checklist
- Daily health monitoring

---

## Installation

See [INSTALL.md](INSTALL.md) for detailed installation instructions.

## Documentation

- **[Configuration Guide](docs/CONFIGURATION_GUIDE.md)** - Detailed configuration options and best practices
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[RShim Guide](docs/RSHIM_GUIDE.md)** - Understanding and managing RShim
- **[Spectrum-X Guide](docs/SPECTRUM_X_GUIDE.md)** - Spectrum-X accelerations explained
- **[Network Configuration Guide](docs/NETWORK_GUIDE.md)** - 8-rail network setup details

## Requirements

### Software Prerequisites
- **Operating System**: RHEL 8/9, Rocky Linux 8/9, or Alma Linux 8/9
- **DOCA/MLNX OFED**: Mellanox Software Tools (MST) or DOCA-Host package
- **RShim**: rshim package installed and enabled
- **NetworkManager**: For IP configuration (default on RHEL/Rocky)
- **Kernel**: 4.18+ (RHEL 8) or 5.14+ (RHEL 9)

### Hardware Prerequisites
- NVIDIA BlueField-3 DPU cards in SuperNIC mode
- PCIe Gen5 x16 slots (Gen4 compatible but reduced performance)
- Adequate cooling (cards can be thermally throttled)

### Permissions
Most scripts require root/sudo access for:
- Reading/writing card configurations via mlxconfig
- Managing systemd services
- Configuring network interfaces
- Restarting rshim service

## Configuration Files

### /etc/rshim.conf
**Critical setting for multiple cards:** 
This sometimes occurs when you don't see all the rshim devices associated with the devices.
It was observed in RHEL 8, that **uio_pci_generic** was grabbing the rshim devices first, and then doesn't present all the devices.
```
FORCE_MODE     1
```
Without this, only 3-5 cards may get rshim devices. See [RShim Guide](docs/RSHIM_GUIDE.md).

### Network Configuration
Edit `scripts/bluefield-configure-ips.sh` configuration section:
```bash
BASE_IP="192.168"           # Your base IP network
GATEWAY_OCTET="254"         # Gateway last octet
MTU=9216                    # MTU size
```

### Interface Names
Update `IFACES` array in scripts if your interface names differ:
```bash
IFACES=(
    "ens32f0np0"  # Your actual interface names
    "ens33f0np0"
    ...
)
```

## Common Workflows

### Initial Deployment

```bash
# 1. Check current state
./scripts/bluefield-status.sh > initial-status.txt

# 2. Fix RShim access (--fix-rshim will make the actual change, otherwise it will dry-run)
sudo ./scripts/bluefield-rshim-check.sh --fix-rshim

# 3. Update firmware (if needed)
for i in {0..7}; do
    sudo bfb-install --bfb firmware.bfb --rshim rshim${i}
done
sudo reboot

# 4. Configure Spectrum-X
sudo ./scripts/setup-spectrum-x-rhel.sh

# 5. Configure network IPs
sudo ./scripts/bluefield-configure-ips.sh 4  # your host ID

# 6. Verify everything
./scripts/bluefield-quick-check.sh
```

### After Firmware Update

```bash
# 1. Verify all cards accessible
./scripts/bluefield-quick-check.sh

# 2. Re-check RShim (settings may have changed)
sudo ./scripts/bluefield-rshim-check.sh --fix-rshim

# 3. Verify Spectrum-X settings (they reset on firmware update)
./scripts/bluefield-status.sh | grep -A3 "Spectrum-X"

# 4. Reapply if needed (service should do this automatically)
sudo systemctl restart spectrum-x-roce.service
```

### Regular Maintenance

```bash
# Weekly health check
./scripts/bluefield-quick-check.sh

# Monthly detailed check
./scripts/bluefield-status.sh > monthly-report-$(date +%Y%m%d).txt

# After any system changes
sudo ./scripts/bluefield-rshim-check.sh
./scripts/bluefield-status.sh
```

### Troubleshooting

```bash
# Full diagnostic dump
./scripts/bluefield-status.sh > bluefield-diagnostic.txt

# Check specific issues
sudo ./scripts/bluefield-rshim-check.sh           # RShim problems
sudo journalctl -u spectrum-x-roce.service        # Spectrum-X logs
sudo journalctl -u rshim.service                  # RShim service logs
nmcli con show                                    # Network configuration
ip route show table all                           # Routing tables
```

## Key Configuration Parameters

### SuperNIC Mode (All Cards Should Show)
| Parameter | SuperNIC Value | Description |
|-----------|---------------|-------------|
| `INTERNAL_CPU_OFFLOAD_ENGINE` | DISABLED(1) | SuperNIC mode active |
| `INTERNAL_CPU_MODEL` | EMBEDDED_CPU(1) | Internal CPU model |
| `INTERNAL_CPU_RSHIM` | ENABLED(0) | Allow firmware updates |
| `LINK_TYPE_P1` | ETH(2) | Ethernet mode (not IB) |

### RoCE Configuration
| Parameter | Expected Value | Description |
|-----------|---------------|-------------|
| `ROCE_CONTROL` | ROCE_ENABLE(2) | RoCE v2 fully enabled |
| `ROCE_ADAPTIVE_ROUTING_EN` | True(1) | Adaptive routing enabled |
| `USER_PROGRAMMABLE_CC` | True(1) | Programmable congestion control |
| `ROCE_CC_PRIO_MASK_P1` | 255 | All priorities enabled |

### Spectrum-X Accelerations
| Register | Expected Value | Description |
|----------|---------------|-------------|
| `roce_tx_window_en` | 0x00000001 | TX window optimization |
| `adaptive_routing_forced_en` | 0x00000001 | Forced adaptive routing |
| `roce_adp_retrans_en` | 0x00000001 | Adaptive retransmission |

**Note**: Spectrum-X settings reset to 0x00000000 on reboot, which is why the systemd service is needed.

## Network Configuration Details

### 8-Rail Spectrum-X Fabric

Each BlueField card connects to a dedicated rail with isolated routing:

```
Rail 1: 192.168.1.x/24  → Table 101 → Leaf Switch 1 VLAN 1
Rail 2: 192.168.2.x/24  → Table 102 → Leaf Switch 1 VLAN 2
Rail 3: 192.168.3.x/24  → Table 103 → Leaf Switch 1 VLAN 3
Rail 4: 192.168.4.x/24  → Table 104 → Leaf Switch 1 VLAN 4
Rail 5: 192.168.5.x/24  → Table 105 → Leaf Switch 2 VLAN 5
Rail 6: 192.168.6.x/24  → Table 106 → Leaf Switch 2 VLAN 6
Rail 7: 192.168.7.x/24  → Table 107 → Leaf Switch 2 VLAN 7
Rail 8: 192.168.8.x/24  → Table 108 → Leaf Switch 2 VLAN 8
```

### Policy-Based Routing
- Each rail has its own routing table
- Source-based routing ensures traffic exits correct interface
- Limiter route prevents accidental internet/management routing through rails
- MTU 9216 for optimal performance

## Systemd Services

### spectrum-x-roce.service
**Location**: `/etc/systemd/system/spectrum-x-roce.service`  
**Purpose**: Applies Spectrum-X RoCE accelerations at boot  
**Script**: `/usr/local/bin/configure-spectrum-x-rhel.sh`

**Management**:
```bash
sudo systemctl status spectrum-x-roce.service    # Check status
sudo systemctl restart spectrum-x-roce.service   # Reapply settings
sudo journalctl -u spectrum-x-roce.service       # View logs
```

## Example Outputs

### Healthy System (bluefield-quick-check.sh)
```
✓ BlueField-3 Cards: 8 detected
✓ RShim Devices: 8 present
✓ RDMA Devices: 9 active (8 BlueField + 1 other)
✓ Spectrum-X Accelerations: Enabled on all cards
✓ Network Interfaces: 8/8 UP
Status: HEALTHY
```

### After Firmware Update (needs Spectrum-X reconfig)
```
✓ BlueField-3 Cards: 8 detected
✓ RShim Devices: 8 present
✓ RDMA Devices: 9 active
⚠ Spectrum-X Accelerations: Not enabled
  Run: sudo systemctl restart spectrum-x-roce.service
```

## Support & Contributions

### Getting Help
1. Check the [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
2. Review script output and system logs
3. Generate diagnostic report: `./scripts/bluefield-status.sh > diagnostic.txt`

### Reporting Issues
When reporting issues, please include:
- Output from `bluefield-status.sh`
- Output from `bluefield-quick-check.sh`
- Relevant log entries: `journalctl -u rshim.service` and `journalctl -u spectrum-x-roce.service`
- OS version: `cat /etc/redhat-release`
- Firmware version from status output

### Contributing
Contributions welcome! Areas for improvement:
- Additional validation checks
- More detailed troubleshooting
- Support for other distributions
- Web-based monitoring dashboard

## Version History

### v1.0.0 (2024-02-18)
**Initial Release**
- ✅ Comprehensive status checking (bluefield-status.sh)
- ✅ RShim management with auto-fix (bluefield-rshim-check.sh)
- ✅ Spectrum-X configuration (setup-spectrum-x-rhel.sh)
- ✅ 8-rail network configuration (bluefield-configure-ips.sh)
- ✅ Quick health checks (bluefield-quick-check.sh)
- ✅ Full documentation suite
- ✅ RHEL/Rocky/Alma Linux support

**Tested On**:
- RHEL 8.10
- DOCA 3.2.1 LTS firmware

**Hardware Tested**:
- Dell PowerEdge servers
- 8x BlueField-3 B3140H SuperNIC Mode (900-9D3D4-00EN-HA0_Ax)

## Acknowledgments

- Based on NVIDIA BlueField documentation and best practices
- Adapted from NVIDIA's Ubuntu networkd-dispatcher scripts for RHEL/Rocky Linux systemd environment
- Community contributions and testing

---

**For detailed documentation, see the [docs/](docs/) directory.**

**For installation instructions, see [INSTALL.md](INSTALL.md).**
