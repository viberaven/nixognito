{ pkgs ? import <nixpkgs> {} }:

let
  # Import the flake configuration
  flake = builtins.getFlake (toString ./.);

  # Build script for the SD image
  buildScript = pkgs.writeScriptBin "build-nixognito-image" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    echo "Building Nixognito SD card image ..."

    # Check if we're on x86_64 (cross-compile) or aarch64 (native)
    ARCH=$(${pkgs.coreutils}/bin/uname -m)

    if [[ "$ARCH" == "x86_64" ]]; then
      echo "Cross-compiling from x86_64 to aarch64..."
      nix build .#packages.x86_64-linux.sdImage --out-link result-sd-image
    elif [[ "$ARCH" == "aarch64" ]]; then
      echo "Building natively on aarch64..."
      nix build .#packages.aarch64-linux.sdImage --out-link result-sd-image
    else
      echo "Unsupported architecture: $ARCH"
      exit 1
    fi

    echo "Build completed. Image available at: result-sd-image/sd-image-nixognito.img.zst"

    # Show image information
    if [[ -f "result-sd-image/sd-image-nixognito.img.zst" ]]; then
      echo "Image size: $(${pkgs.coreutils}/bin/du -h result-sd-image/sd-image-nixognito.img.zst | cut -f1)"
      echo ""
      echo "To flash to SD card:"
      echo "  ${pkgs.zstd}/bin/zstd -d result-sd-image/sd-image-nixognito.img.zst"
      echo "  sudo dd if=sd-image-nixognito.img of=/dev/sdX bs=4M status=progress"
      echo ""
      echo "To test with QEMU (after decompression):"
      echo "  ${pkgs.qemu}/bin/qemu-system-aarch64 \\"
      echo "    -M virt -cpu cortex-a57 -m 2G \\"
      echo "    -drive format=raw,file=sd-image-nixognito.img \\"
      echo "    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \\"
      echo "    -nographic"
    else
      echo "Error: Image file not found after build"
      exit 1
    fi
  '';

  # Test script for the configuration
  testScript = pkgs.writeScriptBin "test-nixognito-config" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    echo "Testing NixOS configuration..."

    # Build the system configuration without creating an image
    nix build .#nixosConfigurations.nixognito.config.system.build.toplevel

    echo "Configuration test passed!"

    # Show some information about the configuration
    echo ""
    echo "Configuration details:"
    echo "- Target platform: aarch64-linux"
    echo "- SSH: Available over USB serial console"
    echo "- Network: All traffic routed through Tor"
    echo "- WiFi: Configured from /etc/wifi-credentials.txt"
    echo "- Security: Direct internet access blocked"
  '';

  # Setup script for development environment
  setupScript = pkgs.writeScriptBin "setup-dev-env" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    echo "Setting up development environment for Nixognito ..."

    # Create example WiFi credentials file
    if [[ ! -f "wifi-credentials-example.txt" ]]; then
      cat > wifi-credentials-example.txt << EOF
# WiFi credentials file example
# Format: SSID=password
# Copy to /etc/wifi-credentials.txt on the target device
MyHomeNetwork=mypassword123
OfficeWiFi=officepassword456
MobileHotspot=hotspotpassword789
EOF
      echo "Created wifi-credentials-example.txt"
    fi

    # Create README
    if [[ ! -f "README-build.md" ]]; then
      cat > README-build.md << 'EOF'
# Nixognito Build Instructions

This NixOS configuration creates an SD card image for Single Board Computers with:
- SSH access over USB serial console
- WiFi with credentials from text file
- All traffic routed through Tor
- Direct internet access blocked

## Building the Image

### Prerequisites
- Nix with flakes enabled
- Either x86_64-linux (cross-compile) or aarch64-linux (native)

### Build Commands

```bash
# Build the SD card image
nix build .#sdImage

# Or use the build script
./result/bin/build-nixognito-image
```

### Testing Configuration

```bash
# Test the configuration (without building image)
./result/bin/test-nixognito-config
```

## Flashing to SD Card

1. Decompress the image:
   ```bash
   zstd -d sd-image-nixognito.img.zst
   ```

2. Flash to SD card (replace /dev/sdX with your SD card device):
   ```bash
   sudo dd if=sd-image-nixognito.img of=/dev/sdX bs=4M status=progress
   sync
   ```

## First Boot Setup

1. Insert SD card into SCB board
2. Connect USB cable to host computer
3. Boot the board
4. Connect to serial console (usually /dev/ttyACM0 or /dev/ttyUSB0)
5. Edit /etc/wifi-credentials.txt with your WiFi details
6. Reboot to connect to WiFi and activate Tor routing

## WiFi Configuration

Create `/etc/wifi-credentials.txt` with format:
```
SSID=password
AnotherNetwork=anotherpassword
```

## Security Features

- All outbound traffic routed through Tor
- Direct internet connections blocked by iptables
- IPv6 disabled to prevent leaks
- DNS queries routed through Tor
- Network monitoring and leak detection
- SSH hardened with key-only authentication

## SSH Access

SSH is available through the USB serial console. The system auto-logs in as the `nixos` user, which has sudo privileges.

To connect from host computer:
```bash
screen /dev/ttyACM0 115200
# or
minicom -D /dev/ttyACM0 -b 115200
```
EOF
      echo "Created README-build.md"
    fi

    echo ""
    echo "Development environment ready!"
    echo "Next steps:"
    echo "1. Edit wifi-credentials-example.txt with your networks"
    echo "2. Run: nix develop"
    echo "3. Run: build-nixognito-image"
  '';

in
{
  inherit buildScript testScript setupScript;

  # Make all scripts available
  scripts = pkgs.symlinkJoin {
    name = "nixognito-scripts";
    paths = [ buildScript testScript setupScript ];
  };
}
