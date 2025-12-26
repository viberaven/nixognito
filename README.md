# Nixognito

A hardened NixOS configuration for single board computers that routes all traffic through Tor with SSH access over USB ethernet.

## Features

- **SSH over USB Ethernet**: Access the system through USB ethernet gadget
- **Interactive WiFi Setup**: Run `wifi-setup` command to connect to WiFi networks
- **Tor Transparent Proxy**: All network traffic automatically routed through Tor
- **Network Isolation**: Direct internet connections blocked by iptables rules
- **Security Hardening**: IPv6 disabled, DNS leak protection, traffic monitoring
- **Cross-platform Build**: Supports building on x86_64 and aarch64 systems

## Quick Start

### Prerequisites

```bash
# Enable Nix flakes
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### Building the SD card image on macOS (Apple Silicon)

This project builds NixOS images for Linux (aarch64-linux). On macOS, you need a Linux environment via [OrbStack](https://orbstack.dev/).

```bash
# Clone and enter directory
git clone <this-repo>
cd nixognito

# Create a NixOS VM (or use Ubuntu/Debian and install Nix)
orb create nixos

# Enter the VM
orb shell -m nixos

# Edit /etc/nixos/configuration.nix and add the following line:
# nix.settings.experimental-features = [ "nix-command" "flakes" ];

# Rebuild NixOS
nixos-rebuild switch --upgrade
```

Then follow the Linux build instructions below.

### Build the SD card image on Linux

```bash
# Clone and enter directory
git clone <this-repo>
cd nixognito

# Build the SD card image
nix build .#sdImage
```

### Flash the SD card image to SD card

```bash
# Flash to SD card (replace /dev/sdX with your device)
sudo dd if=result/sd-image/nixognito-radxa-zero3w.img of=/dev/sdX bs=4M status=progress oflag=sync
```

## Configuration Files

- `configuration.nix` - Main system configuration (users, packages, boot)
- `hardware-configuration.nix` - Radxa Zero 3W hardware settings and kernel modules
- `networking.nix` - NetworkManager, WiFi setup script, firewall basics
- `tor-proxy.nix` - Tor service, transparent proxy, service dependencies (see design docs)
- `usb-ssh.nix` - USB gadget ethernet for SSH access over USB
- `security-hardening.nix` - Additional security hardening rules
- `flake.nix` - Nix flake with build targets

## First Boot Setup

1. Insert SD card into Radxa Zero 3W board
2. Connect USB-C cable between board's USB-C port and your computer
3. Power on the board (wait ~30 seconds for boot)

### macOS Setup

When you connect the board, macOS will create a new network interface. Configure it:

```bash
# Find the interface name (e.g., en7)
networksetup -listallhardwareports | grep -A1 "RNDIS/Ethernet"
# Or check System Settings → Network for "RNDIS/Ethernet Gadget"

# Assign an IP to the macOS side (replace en7 with your interface)
sudo ifconfig en7 192.168.64.1 netmask 255.255.255.0 up

# SSH to the board (password: nixognito)
ssh nixos@192.168.64.2
```

Alternatively, enable **Internet Sharing** in System Settings:
1. Go to **System Settings → General → Sharing → Internet Sharing**
2. Share your WiFi/Ethernet to the new USB interface
3. The board will get an IP via DHCP

### Linux Setup

```bash
# Find the new interface (usually usb0 or enp0s*)
ip link show

# Assign an IP
sudo ip addr add 192.168.64.1/24 dev <interface>
sudo ip link set <interface> up

# SSH to the board (password: nixognito)
ssh nixos@192.168.64.2
```

### Connect to WiFi

Once logged in via SSH, run the WiFi setup wizard:

```bash
wifi-setup
```

This will scan for available networks and prompt for credentials.

## Security Model

### Network Initialization Flow

The system follows a strict initialization sequence to ensure Tor works correctly:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. BOOT                                                                 │
│    └─► USB Ethernet active (192.168.64.2)                               │
│        └─► SSH available for user access                                │
│            └─► NO internet connectivity yet                             │
├─────────────────────────────────────────────────────────────────────────┤
│ 2. USER ACTION                                                          │
│    └─► User SSHs in via USB ethernet                                    │
│        └─► User runs `wifi-setup`                                       │
│            └─► Board connects to WiFi                                   │
├─────────────────────────────────────────────────────────────────────────┤
│ 3. wifi-online.service                                                  │
│    └─► Detects wlan0 has default route                                  │
│        └─► Verifies internet connectivity (ping 1.1.1.1)                │
│            └─► Triggers dependent services                              │
├─────────────────────────────────────────────────────────────────────────┤
│ 4. systemd-timesyncd (requires: wifi-online)                            │
│    └─► Starts NTP daemon                                                │
│        └─► DIRECT internet access (bypasses Tor)                        │
│            └─► Contacts NTP servers to sync clock                       │
├─────────────────────────────────────────────────────────────────────────┤
│ 5. time-synced.service (requires: timesyncd)                            │
│    └─► Waits for NTPSynchronized=yes                                    │
│        └─► Ensures clock is actually synced before proceeding           │
│            └─► Tor requires accurate time for certificate validation    │
├─────────────────────────────────────────────────────────────────────────┤
│ 6. tor.service (requires: time-synced, wifi-online)                     │
│    └─► Starts Tor daemon                                                │
│        └─► Establishes Tor circuits                                     │
│            └─► Opens SOCKS (9050), TransPort (9040), DNS (5353)         │
├─────────────────────────────────────────────────────────────────────────┤
│ 7. tor-transparent-proxy.service (requires: tor)                        │
│    └─► Configures iptables rules                                        │
│        └─► Redirects all TCP to Tor TransPort                           │
│            └─► Redirects all DNS to Tor DNSPort                         │
│                └─► Blocks non-Tor traffic                               │
├─────────────────────────────────────────────────────────────────────────┤
│ 8. OPERATIONAL STATE                                                    │
│    └─► All traffic forced through Tor                                   │
│        └─► Only tor and timesyncd can access internet directly          │
│            └─► All other processes use Tor or are blocked               │
└─────────────────────────────────────────────────────────────────────────┘
```

### Direct Internet Access (Tor Bypass)

Only two system users can access the internet directly:

| User | Purpose | Why Direct Access? |
|------|---------|-------------------|
| `tor` | Tor daemon | Must connect to Tor relays directly |
| `systemd-timesync` | NTP time sync | Accurate time required before Tor can start |

All other processes are forced through Tor's transparent proxy or rejected.

### Network Isolation
- All outbound TCP traffic redirected through Tor (port 9040)
- DNS queries routed through Tor DNS proxy (port 5353)
- Direct internet access blocked by iptables REJECT rules
- Local network access preserved (192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12)
- USB ethernet (192.168.64.0/24) always accessible for management

### System Hardening
- IPv6 completely disabled
- ICMP redirects disabled
- Source routing disabled
- Reverse path filtering enabled

## Network Architecture

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│   Client    │────│ USB Ethernet │────│   Radxa     │
│  Computer   │    │  (192.168.   │    │  Zero 3W    │
│ 192.168.64.1│    │   64.0/24)   │    │ 192.168.64.2│
└─────────────┘    └──────────────┘    └─────────────┘
                                              │
                                              │ WiFi (wlan0)
                                              ▼
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│  Internet   │◄───│     Tor      │◄───│   Router    │
│             │    │   Network    │    │             │
└─────────────┘    └──────────────┘    └─────────────┘
```

## Build Targets

```bash
# Build SD image for current architecture
nix build .#sdImage

# Cross-compile from x86_64 to aarch64
nix build .#packages.x86_64-linux.sdImage

# Test configuration without building image
nix build .#nixosConfigurations.nixognito.config.system.build.toplevel

# Enter development shell
nix develop
```

## Customization

### Tor Configuration

Modify `tor-proxy.nix` to customize Tor settings:

```nix
services.tor.settings = {
  ExitNodes = "{us}";      # Specify exit countries
  UseBridges = true;       # Enable bridge mode
  StrictNodes = true;      # Enforce node restrictions
};
```

### Network Monitoring

Adjust monitoring intervals in `security-hardening.nix`:

```nix
systemd.services.network-lockdown.timer = {
  OnCalendar = "*:0/1";  # Check every minute
};
```

## Troubleshooting

### USB Ethernet Not Working
- Check USB-C cable connection (must support data, not just charging)
- Verify interface appeared: `ifconfig` (macOS) or `ip link` (Linux)
- Check board booted: wait 30+ seconds after power on
- Try a different USB port

### WiFi Not Connecting
- Run `wifi-setup` to reconfigure
- Check available networks: `nmcli dev wifi list`
- Monitor logs: `journalctl -f -u NetworkManager`

### Tor Not Starting
- Check service chain: `systemctl status wifi-online systemd-timesyncd time-synced tor`
- WiFi must be connected first - run `wifi-setup`
- Monitor initialization: `journalctl -f -u wifi-online -u systemd-timesyncd -u time-synced -u tor`
- Check time sync: `timedatectl status`

### Tor Connection Issues
- Check Tor status: `systemctl status tor`
- Test SOCKS proxy: `curl --socks5 127.0.0.1:9050 https://check.torproject.org/api/ip`
- View Tor logs: `journalctl -f -u tor`
- Check transparent proxy: `systemctl status tor-transparent-proxy`

### Network Leaks
- Test Tor routing: `curl https://check.torproject.org/api/ip` (should show `IsTor: true`)
- Check iptables rules: `iptables -t nat -L OUTPUT -v -n`
- Check filter rules: `iptables -L OUTPUT -v -n`

## Development

### Project Structure
```
├── configuration.nix           # Main system configuration
├── hardware-configuration.nix  # Radxa Zero 3W hardware support
├── networking.nix              # NetworkManager, WiFi setup script
├── tor-proxy.nix               # Tor transparent proxy + service dependencies
├── usb-ssh.nix                 # USB gadget ethernet (g_ether)
├── security-hardening.nix      # Additional security rules
├── flake.nix                   # Nix flake configuration
└── README.md                   # This file
```

### Testing Changes

```bash
# Test configuration syntax
nix flake check

# Build configuration only
nix build .#nixosConfigurations.nixognito.config.system.build.toplevel

# Full image build
nix build .#sdImage
```

### Contributing

1. Test changes thoroughly with `nix flake check`
2. Verify security model isn't compromised
3. Update documentation for new features
4. Test on actual SBC hardware when possible

## License

This configuration is provided as-is for educational and defensive security purposes only.
