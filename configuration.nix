{ config, pkgs, lib, ... }:

{
  imports = [
    ./networking.nix
    ./tor-proxy.nix
    ./usb-ssh.nix
    ./security-hardening.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  boot = {
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };

    # Use LTS kernel instead of latest (smaller, more stable)
    kernelPackages = pkgs.linuxPackages;
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  system.stateVersion = "25.11";

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
      PubkeyAuthentication = true;
      PrintMotd = true;
    };
    listenAddresses = [
      { addr = "0.0.0.0"; port = 22; }
    ];
  };

  users.motd = ''

    ========================================
             Welcome to Nixognito
    ========================================

    Run 'wifi-setup' to connect to a WiFi network.

  '';

  services.getty = {
    autologinUser = "nixos";
    helpLine = lib.mkForce "";
  };

  users = {
    mutableUsers = false;
    users = {
      root = {
        hashedPassword = "!";
      };
      nixos = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager" "dialout" ];
        # password is "nixognito"
        hashedPassword = "$6$dwUfeM9UGGRwlY2v$CoCMREevu51ik384HWlB91QZAfdgDwVi5SzVkHM6OOEb1pGKBmZN28IWJ9YShiVDXSXsgQ/Nc4lIC8qli6HCX.";
      };
    };
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    git
    htop
    nano
    tmux
    vim
  ];

  powerManagement.cpuFreqGovernor = "ondemand";

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Disable documentation to reduce image size
  documentation = {
    enable = false;
    doc.enable = false;
    info.enable = false;
    man.enable = false;
    nixos.enable = false;
  };

  # Disable unused services and features
  programs.command-not-found.enable = false;
  services.udisks2.enable = false;
  xdg.sounds.enable = false;
  xdg.mime.enable = false;

  # Exclude large packages from closure
  environment.defaultPackages = lib.mkForce [];
}
