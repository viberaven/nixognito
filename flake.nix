{
  description = "Nixognito - NixOS-based privacy-focused Tor router for single board computers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs, ... }:
  let
    gitRev = self.shortRev or self.dirtyShortRev or "unknown";

    mkNixognitoSystem = { device, buildPlatform ? "aarch64-linux" }:
      nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image.nix"
          ./configuration.nix
          ./devices/${device}

          ({ config, lib, pkgs, ... }: {
            nixpkgs.hostPlatform = "aarch64-linux";

            image.baseName = lib.mkForce
              "nixognito-${device}-${gitRev}";

            fileSystems."/" = lib.mkForce {
              device = "/dev/disk/by-label/NIXOS_SD";
              fsType = "ext4";
            };
          } // lib.optionalAttrs (buildPlatform == "x86_64-linux") {
            nixpkgs.buildPlatform = "x86_64-linux";
          })
        ];
      };

    devices = [ "radxa-zero3w" "rpi-zero2w" ];

  in {
    # NixOS configurations for each device
    nixosConfigurations = builtins.listToAttrs (map (device: {
      name = "nixognito-${device}";
      value = mkNixognitoSystem { inherit device; };
    }) devices);

    # SD image packages for each device and build platform
    packages.aarch64-linux = builtins.listToAttrs (map (device: {
      name = "sdImage-${device}";
      value = (mkNixognitoSystem { inherit device; }).config.system.build.sdImage;
    }) devices);

    packages.x86_64-linux = builtins.listToAttrs (map (device: {
      name = "sdImage-${device}";
      value = (mkNixognitoSystem {
        inherit device;
        buildPlatform = "x86_64-linux";
      }).config.system.build.sdImage;
    }) devices);

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
            echo ""
            echo "Build SD images:"
            echo "  nix build .#sdImage-radxa-zero3w"
            echo "  nix build .#sdImage-rpi-zero2w"
          '';
        };
      });
  };
}
