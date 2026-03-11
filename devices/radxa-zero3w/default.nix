{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/base.nix")
    ./aic8800.nix
  ];

  # --- Image ---
  image.baseName = "nixognito-radxa-zero3w";

  # --- Hardware ---
  hardware.deviceTree = {
    enable = true;
    name = "rockchip/rk3566-radxa-zero-3w.dtb";
  };

  hardware = {
    enableRedistributableFirmware = lib.mkForce false;
    firmware = with pkgs; [ wireless-regdb ];
  };

  # --- Boot ---
  boot = {
    initrd.availableKernelModules = [
      "mmc_block"
      "sdhci_of_dwcmshc"
      "phy_rockchip_inno_usb2"
      "dwc3"
      "dwc3_of_simple"
      "ohci_platform"
      "ehci_platform"
    ];

    kernelModules = [ "rk_crypto" ];

    blacklistedKernelModules = [
      # GPU/display - not needed
      "panfrost"
      "rockchipdrm"
      # Video codecs - not needed
      "hantro_vpu"
      "rockchip_vdec"
      "rockchip_rga"
    ];

    kernelParams = [
      "console=ttyS2,1500000"
      "earlycon=uart8250,mmio32,0xfe660000"
      "earlyprintk"
    ];
  };

  # --- SD Image ---
  sdImage =
    let
      uboot = pkgs.ubootRadxaZero3W;
    in {
      compressImage = false;

      # Rockchip u-boot goes at sector 64 (32KB) and can be up to ~4MB
      # Start firmware partition after u-boot area (at 32MiB to be safe)
      firmwarePartitionOffset = 32;
      firmwareSize = 32;
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

  # --- Udev ---
  services.udev.extraRules = ''
    # USB gadget serial console
    KERNEL=="ttyGS*", GROUP="dialout", MODE="0666"

    # Rockchip USB gadget
    SUBSYSTEM=="usb", ATTR{idVendor}=="2207", ATTR{idProduct}=="0018", MODE="0666", GROUP="plugdev"
  '';

  # --- LED ---
  systemd.services.disable-led = {
    description = "Disable green LED";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo none > /sys/class/leds/green:heartbeat/trigger'";
    };
  };
}
