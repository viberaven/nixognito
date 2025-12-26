{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/base.nix")
  ];

  boot.initrd.availableKernelModules = [
    "mmc_block"
    "sdhci_of_dwcmshc"
    "phy_rockchip_inno_usb2"
    "dwc3"
    "dwc3_of_simple"
    "ohci_platform"
    "ehci_platform"
    "usbhid"
    "usb_storage"
    "uas"
  ];

  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "rk_crypto"
  ];
  boot.extraModulePackages = [ ];
  boot.blacklistedKernelModules = [
    # GPU/display - not needed
    "panfrost"
    "rockchipdrm"
    # Video codecs - not needed
    "hantro_vpu"
    "rockchip_vdec"
    "rockchip_rga"
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  # Note: /boot is part of the root filesystem for SD card images
  # fileSystems."/boot" is not needed with extlinux boot

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault false;

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  hardware.deviceTree = {
    enable = true;
    name = "rockchip/rk3566-radxa-zero-3w.dtb";
  };

  services.udev.extraRules = ''
    # USB gadget serial console
    KERNEL=="ttyGS*", GROUP="dialout", MODE="0666"

    # Rock chip USB gadget
    SUBSYSTEM=="usb", ATTR{idVendor}=="2207", ATTR{idProduct}=="0018", MODE="0666", GROUP="plugdev"
  '';


}
