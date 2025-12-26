{
  description = "Nixognito - NixOS-based privacy-focused Tor router for Radxa Zero 3W";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
  let
    gitRev = self.shortRev or self.dirtyShortRev or "unknown";
    mkNixognitoSystem = { buildPlatform ? "aarch64-linux" }:
      nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image.nix"
          ./configuration.nix
          ./hardware-configuration.nix
          ./networking.nix
          ./tor-proxy.nix
          ./usb-ssh.nix
          ./security-hardening.nix

          ({ config, lib, pkgs, ... }: {
            nixpkgs.hostPlatform = "aarch64-linux";
          } // lib.optionalAttrs (buildPlatform == "x86_64-linux") {
            nixpkgs.buildPlatform = "x86_64-linux";
          })

          ({ config, lib, pkgs, ... }:
          let
            uboot = pkgs.ubootRadxaZero3W;
          in {
            boot.loader.grub.enable = false;
            boot.loader.generic-extlinux-compatible.enable = true;

            image.baseName = "nixognito-radxa-zero3w-${gitRev}";

            sdImage = {
              compressImage = false;

              # Rockchip u-boot goes at sector 64 (32KB) and can be up to ~4MB
              # Start firmware partition after u-boot area (at 16MB to be safe)
              firmwarePartitionOffset = 32;  # In MiB, start at 32MiB
              firmwareSize = 32;  # 32 MiB firmware partition
              populateFirmwareCommands = "";

              postBuildCommands = ''
                # Write u-boot at sector 64 (32KB offset) as required by Rockchip
                dd if=${uboot}/u-boot-rockchip.bin of=$img seek=64 conv=notrunc bs=512
              '';

              populateRootCommands = ''
                mkdir -p ./files/boot/extlinux
                ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
              '';
            };

            fileSystems."/" = lib.mkForce {
              device = "/dev/disk/by-label/NIXOS_SD";
              fsType = "ext4";
            };
          })
        ];
      };
  in {
    nixosConfigurations.nixognito = mkNixognitoSystem {};

    packages.aarch64-linux.sdImage = self.nixosConfigurations.nixognito.config.system.build.sdImage;

    packages.x86_64-linux.sdImage = (mkNixognitoSystem { buildPlatform = "x86_64-linux"; }).config.system.build.sdImage;

    devShells = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixos-rebuild
            git
            qemu
            zstd
            dtc
            ubootTools
          ];

          shellHook = ''
            echo "Nixognito Development Environment"
            echo "Platform: ${system}"
            echo "Build SD image: nix build .#sdImage"
          '';
        };
      });
  };
}
