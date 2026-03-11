{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/base.nix")
  ];

  # --- Image ---
  image.baseName = "nixognito-rpi-zero2w";

  # --- Hardware ---
  hardware.deviceTree = {
    enable = true;
    name = "broadcom/bcm2837-rpi-zero-2-w.dtb";
  };

  # RPi needs redistributable firmware for WiFi (brcmfmac)
  hardware = {
    enableRedistributableFirmware = true;
    firmware = with pkgs; [ wireless-regdb ];
  };

  # --- Boot ---
  boot = {
    initrd.availableKernelModules = [
      "mmc_block"
      "sdhci_pltfm"
      "bcm2835_dma"
      "dwc2"
      "udc_core"
      "ohci_platform"
      "ehci_platform"
      "usbhid"
      "usb_storage"
    ];

    kernelModules = [
      "dwc2"        # USB OTG controller (needed for USB gadget)
      "brcmfmac"    # Broadcom WiFi driver
    ];

    blacklistedKernelModules = [
      # GPU/display - not needed for headless Tor router
      "vc4"
      "v3d"
    ];

    kernelParams = [
      "console=ttyAMA0,115200"
      "earlyprintk"
    ];
  };

  # --- SD Image ---
  sdImage =
    let
      uboot = pkgs.ubootRaspberryPi3_64bit;
    in {
      compressImage = false;

      # RPi firmware partition
      firmwarePartitionOffset = 8;
      firmwareSize = 128;

      populateFirmwareCommands = ''
        # Copy Raspberry Pi firmware files
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bootcode.bin firmware/
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/fixup.dat firmware/
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/start.elf firmware/

        # Copy device tree for RPi Zero 2W (required by start.elf)
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2710-rpi-zero-2-w.dtb firmware/

        # Copy device tree overlays
        cp -r ${pkgs.raspberrypifw}/share/raspberrypi/boot/overlays firmware/

        # Copy U-Boot binary
        cp ${uboot}/u-boot.bin firmware/u-boot-rpi-arm64.bin

        # Write config.txt
        cp ${./config.txt} firmware/config.txt
      '';

      postBuildCommands = "";

      populateRootCommands = ''
        mkdir -p ./files/boot/extlinux
        ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
      '';
    };

  # --- Udev ---
  services.udev.extraRules = ''
    # USB gadget serial console
    KERNEL=="ttyGS*", GROUP="dialout", MODE="0666"
  '';

  # --- LED ---
  systemd.services.disable-led = {
    description = "Disable ACT LED";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo none > /sys/class/leds/ACT/trigger 2>/dev/null || true'";
    };
  };
}
