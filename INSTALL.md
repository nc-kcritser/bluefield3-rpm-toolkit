# Installation Guide

Complete installation instructions for the BlueField-3 SuperNIC Management Toolkit.

## Prerequisites

### Operating System
- RHEL 8.x or 9.x
- Rocky Linux 8.x or 9.x
- Alma Linux 8.x or 9.x

### Required Packages

```bash
# Install DOCA or MLNX OFED (provides MST tools)
# Option 1: DOCA (recommended)
sudo dnf install doca-host

# Option 2: MLNX OFED
wget https://www.mellanox.com/downloads/ofed/MLNX_OFED-latest/MLNX_OFED_LINUX-latest-rhel8.x-x86_64.tgz
tar -xzf MLNX_OFED_LINUX-latest-rhel8.x-x86_64.tgz
cd MLNX_OFED_LINUX-*
sudo ./mlnxofedinstall --add-kernel-support

# Install RShim
sudo dnf install rshim

# Ensure NetworkManager is installed and running
sudo dnf install NetworkManager
sudo systemctl enable --now NetworkManager
```

### Verify Prerequisites

```bash
# Check MST tools
which mst
which mlxconfig
which mlxreg

# Check RShim
which bfb-install
systemctl status rshim.service

# Check NetworkManager
systemctl status NetworkManager
```

## Quick Installation

```bash
# 1. Download the toolkit
cd /opt
sudo wget https://[your-repo]/bluefield-toolkit.tar.gz

# 2. Extract
sudo tar -xzf bluefield-toolkit.tar.gz
cd bluefield-toolkit

# 3. Make scripts executable
sudo chmod +x scripts/*.sh
sudo chmod +x systemd/configure-spectrum-x-rhel.sh

# 4. Verify installation
./scripts/bluefield-status.sh
```

## Manual Installation from Git

```bash
# 1. Clone repository
cd /opt
sudo git clone https://[your-repo]/bluefield-toolkit.git
cd bluefield-toolkit

# 2. Make scripts executable
sudo chmod +x scripts/*.sh
sudo chmod +x systemd/configure-spectrum-x-rhel.sh

# 3. Verify
./scripts/bluefield-status.sh
```

## Configuration

### Step 1: Configure RShim (Required for Multiple Cards)

```bash
# Check current RShim configuration
cat /etc/rshim.conf

# If FORCE_MODE is not set to 1, run:
sudo ./scripts/bluefield-rshim-check.sh --fix-rshim

# Or manually edit:
sudo nano /etc/rshim.conf
# Add or uncomment:
FORCE_MODE     1

# Restart rshim service
sudo systemctl restart rshim.service
```

### Step 2: Configure Network Settings (Optional)

Edit the IP configuration script for your environment:

```bash
sudo nano scripts/bluefield-configure-ips.sh

# Modify the configuration section:
BASE_IP="192.168"           # Change to your network (e.g., "10.100")
GATEWAY_OCTET="254"         # Change gateway last octet if needed
MTU=9216                    # Adjust MTU if needed
LIMITER_ROUTE="192.168.0.0/20"  # Adjust to match your network
```

### Step 3: Verify Interface Names

Ensure the interface names in the scripts match your system:

```bash
# Check your actual interface names
ip link show | grep ens

# If different, update the IFACES array in:
# - scripts/bluefield-configure-ips.sh
# - systemd/configure-spectrum-x-rhel.sh

sudo nano scripts/bluefield-configure-ips.sh
# Update IFACES array to match your system
```

### Step 4: Install Spectrum-X Service

```bash
# This creates and enables the systemd service
sudo ./scripts/setup-spectrum-x-rhel.sh

# Verify service is installed
systemctl status spectrum-x-roce.service
```

## Post-Installation Verification

### Verify All Components

```bash
# 1. Check card detection
./scripts/bluefield-status.sh

# Expected output should show:
# - 8 BlueField-3 cards detected
# - Firmware versions
# - All cards in SuperNIC mode

# 2. Check RShim access
sudo ./scripts/bluefield-rshim-check.sh

# Expected output:
# ✓ FORCE_MODE: OK
# ✓ INTERNAL_CPU_RSHIM: OK on all cards
# ✓ RShim devices: 8/8 present
# ✓ RShim service: Running

# 3. Quick health check
./scripts/bluefield-quick-check.sh

# Expected output:
# ✓ BlueField-3 Cards: 8 detected
# ✓ RShim Devices: 8 present
# ✓ RDMA Devices: 8+ active
# ✓ Spectrum-X Accelerations: Enabled
```

### Configure Network (If Needed)

```bash
# Dry run first to preview
./scripts/bluefield-configure-ips.sh 4 --dry-run

# Apply configuration (where 4 is your host ID)
sudo ./scripts/bluefield-configure-ips.sh 4

# Verify network configuration
nmcli con show
ip addr show | grep 192.168
ping -c 3 -I rail1 192.168.1.254
```

## Troubleshooting Installation

### Issue: MST tools not found

```bash
# Check if mst package is installed
rpm -qa | grep mst

# If not, install DOCA or MLNX OFED (see Prerequisites)
```

### Issue: RShim devices not appearing

```bash
# Check rshim service
sudo systemctl status rshim.service
sudo journalctl -u rshim.service -n 50

# Enable FORCE_MODE
sudo ./scripts/bluefield-rshim-check.sh --fix-rshim

# Check if cards have INTERNAL_CPU_RSHIM enabled
sudo mst start
sudo mlxconfig -d /dev/mst/mt41692_pciconf0 q | grep INTERNAL_CPU_RSHIM
# Should show: ENABLED(0)
```

### Issue: Cards not detected

```bash
# Check PCIe detection
lspci -nn | grep 15b3:a2dc

# Should show 8 entries
# If not, check:
# - Physical installation
# - PCIe slot compatibility
# - BIOS settings (PCIe should be enabled)
```

### Issue: Spectrum-X accelerations not persisting

```bash
# Verify service is installed and enabled
systemctl status spectrum-x-roce.service

# Check service logs
sudo journalctl -u spectrum-x-roce.service

# Manually trigger
sudo systemctl restart spectrum-x-roce.service

# Verify settings
for i in {0..7}; do
    iface="ens$((32+i))f0np0"
    pci=$(cat /sys/class/net/$iface/device/uevent | grep PCI_SLOT_NAME | cut -d'=' -f2)
    echo "=== $iface ==="
    sudo mlxreg -d $pci --get --reg_name ROCE_ACCL | grep -E "roce_tx_window_en|adaptive_routing_forced_en"
done
```

### Issue: NetworkManager not managing interfaces

```bash
# Check NetworkManager status
systemctl status NetworkManager

# Check if interfaces are managed
nmcli device status

# If "unmanaged", edit NetworkManager config
sudo nano /etc/NetworkManager/NetworkManager.conf
# Ensure [ifcfg-rh] section doesn't have managed=false

# Restart NetworkManager
sudo systemctl restart NetworkManager
```

## Directory Structure After Installation

```
/opt/bluefield-toolkit/
├── README.md                   # Main documentation
├── INSTALL.md                  # This file
├── scripts/
│   ├── bluefield-status.sh              # Status checking
│   ├── bluefield-rshim-check.sh         # RShim management
│   ├── bluefield-configure-ips.sh       # Network configuration
│   ├── setup-spectrum-x-rhel.sh         # Spectrum-X setup
│   └── bluefield-quick-check.sh         # Quick health check
├── docs/
│   ├── CONFIGURATION_GUIDE.md
│   ├── TROUBLESHOOTING.md
│   ├── RSHIM_GUIDE.md
│   ├── SPECTRUM_X_GUIDE.md
│   └── NETWORK_GUIDE.md
├── configs/
│   ├── rshim.conf.example
│   ├── interfaces.conf.example
│   └── spectrum-x.conf.example
├── systemd/
│   ├── spectrum-x-roce.service
│   └── configure-spectrum-x-rhel.sh
└── examples/
    └── sample-outputs/

/usr/local/bin/
└── configure-spectrum-x-rhel.sh        # Installed by setup script

/etc/systemd/system/
└── spectrum-x-roce.service             # Installed by setup script
```

## Uninstallation

If you need to remove the toolkit:

```bash
# 1. Disable and remove Spectrum-X service
sudo systemctl stop spectrum-x-roce.service
sudo systemctl disable spectrum-x-roce.service
sudo rm /etc/systemd/system/spectrum-x-roce.service
sudo rm /usr/local/bin/configure-spectrum-x-rhel.sh
sudo systemctl daemon-reload

# 2. Remove network connections (optional)
for i in {1..8}; do
    sudo nmcli con delete rail${i} 2>/dev/null
done

# 3. Remove toolkit directory
sudo rm -rf /opt/bluefield-toolkit
```

## Upgrading

To upgrade to a new version:

```bash
# 1. Stop services
sudo systemctl stop spectrum-x-roce.service

# 2. Backup current configuration
cp /opt/bluefield-toolkit/scripts/bluefield-configure-ips.sh ~/bluefield-config-backup.sh

# 3. Remove old version
sudo rm -rf /opt/bluefield-toolkit

# 4. Install new version (follow Quick Installation steps)

# 5. Restore your configuration
# Edit the new scripts with your settings from backup

# 6. Restart services
sudo systemctl start spectrum-x-roce.service
```

## Next Steps

After successful installation:

1. **Read the documentation**: Check [docs/CONFIGURATION_GUIDE.md](docs/CONFIGURATION_GUIDE.md)
2. **Run initial checks**: Use `bluefield-status.sh` to verify configuration
3. **Configure network**: Set up IPs using `bluefield-configure-ips.sh`
4. **Set up monitoring**: Consider adding `bluefield-quick-check.sh` to cron

## Support

For issues during installation:
- Check the [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- Review installation logs
- Ensure all prerequisites are met
- Verify hardware is properly installed

## Security Considerations

- Scripts require root access for most operations
- Review scripts before running with sudo
- Ensure /opt/bluefield-toolkit permissions are appropriate:
  ```bash
  sudo chown -R root:root /opt/bluefield-toolkit
  sudo chmod -R 755 /opt/bluefield-toolkit
  ```
