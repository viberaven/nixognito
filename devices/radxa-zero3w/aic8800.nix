# inspired by https://github.com/NixOS/nixpkgs/pull/443520

{ config, lib, pkgs, ... }:

let
  aic8800-firmware = pkgs.stdenvNoCC.mkDerivation {
    pname = "aic8800-firmware-sdio";
    version = "4.0.20250410";

    src = pkgs.fetchFromGitHub {
      owner = "deepin-community";
      repo = "aic8800";
      rev = "4.0+git20250410.b99ca8b6-4deepin2";
      hash = "sha256-6MRfsuz+dzBvcmZ1gx1h8S/Xjr05ZbLftgb3RJ7Kp3k=";
    };

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/firmware

      # Copy SDIO firmware directly (source files are already .bin, not compressed)
      cp -rv firmware/SDIO/aic8800D80 $out/lib/firmware/
      cp -rv firmware/SDIO/aic8800DC $out/lib/firmware/
      cp -rv firmware/SDIO/aic8800 $out/lib/firmware/

      echo "Firmware files installed:"
      find $out -type f | wc -l

      runHook postInstall
    '';

    meta = {
      description = "Aicsemi aic8800 Wi-Fi driver firmware (SDIO)";
      license = lib.licenses.unfree;
      platforms = lib.platforms.linux;
    };
  };

  aic8800-driver = config.boot.kernelPackages.callPackage ({ lib, stdenv, kernel, kernelModuleMakeFlags }:
    stdenv.mkDerivation {
      name = "aic8800-${kernel.version}";
      version = "4.0.20250410";

      src = pkgs.fetchFromGitHub {
        owner = "deepin-community";
        repo = "aic8800";
        rev = "4.0+git20250410.b99ca8b6-4deepin2";
        hash = "sha256-6MRfsuz+dzBvcmZ1gx1h8S/Xjr05ZbLftgb3RJ7Kp3k=";
      };

      hardeningDisable = [ "pic" ];

      nativeBuildInputs = kernel.moduleBuildDependencies;

      makeFlags = kernelModuleMakeFlags ++ [
        "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      ];

      buildPhase = ''
        runHook preBuild
        cd src/SDIO
        make $makeFlags
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/wireless/aic8800
        find . -name "*.ko" -exec install -Dm444 {} $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/wireless/aic8800/ \;
        runHook postInstall
      '';

      meta = {
        description = "Aicsemi aic8800 Wi-Fi driver (SDIO)";
        license = lib.licenses.gpl2Only;
        platforms = lib.platforms.linux;
      };
    }
  ) {};

in
{
  # Allow unfree firmware
  nixpkgs.config.allowUnfree = true;

  # Disable firmware compression (driver uses custom loader that doesn't support zstd)
  hardware.firmwareCompression = "none";

  # Add firmware
  hardware.firmware = [ aic8800-firmware ];

  # Add kernel module
  boot.extraModulePackages = [ aic8800-driver ];

  # Load the driver on boot
  boot.kernelModules = [ "aic8800_fdrv" ];

  # Create /lib/firmware symlink for out-of-tree drivers that hardcode the path
  system.activationScripts.firmwareSymlink = ''
    mkdir -p /lib
    ln -sfn /run/current-system/firmware /lib/firmware
  '';
}
