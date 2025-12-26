{ config, lib, pkgs, ... }:

{
  networking = {
    hostName = "nixognito";

    # NetworkManager handles WiFi connections
    networkmanager = {
      enable = true;
      wifi.powersave = false;
    };

    # Disable DHCP on interfaces - NetworkManager handles this
    useDHCP = false;
    interfaces.wlan0.useDHCP = false;

    # Basic firewall - Tor transparent proxy rules are in tor-proxy.nix
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];  # SSH access via USB ethernet
    };
  };

  # WiFi setup script for interactive connection
  environment.systemPackages = [ pkgs.wifi-setup-script ];

  nixpkgs.overlays = [
    (final: prev: {
      wifi-setup-script = prev.writeShellScriptBin "wifi-setup" ''
        echo ""
        echo "Nixognito WiFi Setup"
        echo ""

        # Scan for networks
        echo "Scanning for WiFi networks..."
        ${prev.networkmanager}/bin/nmcli device wifi rescan 2>/dev/null || true
        sleep 2
        echo ""
        echo "Available networks:"
        ${prev.networkmanager}/bin/nmcli -t -f SSID,SIGNAL,SECURITY device wifi list | head -20
        echo ""

        # Prompt for SSID
        read -p "Enter WiFi SSID: " ssid
        if [ -z "$ssid" ]; then
          echo "Error: SSID cannot be empty"
          exit 1
        fi

        # Prompt for password (hidden input)
        read -s -p "Enter WiFi password: " password
        echo ""

        if [ -z "$password" ]; then
          echo "Error: Password cannot be empty"
          exit 1
        fi

        echo ""
        echo "Connecting to '$ssid'..."

        # Remove existing connection if present
        ${prev.networkmanager}/bin/nmcli connection delete "$ssid" 2>/dev/null || true

        # Create connection profile with WPA-PSK
        if ${prev.networkmanager}/bin/nmcli connection add \
          type wifi \
          con-name "$ssid" \
          ssid "$ssid" \
          ifname wlan0 \
          wifi-sec.key-mgmt wpa-psk \
          wifi-sec.psk "$password"; then

          # Activate the connection
          if ${prev.networkmanager}/bin/nmcli connection up "$ssid"; then
            echo ""
            echo "Connected to '$ssid' successfully!"
            echo ""
            echo "Tor initialization will begin automatically..."
            echo "Run 'journalctl -f -u wifi-online -u systemd-timesyncd -u time-synced -u tor' to monitor progress"
          else
            echo ""
            echo "Failed to activate connection to '$ssid'"
            ${prev.networkmanager}/bin/nmcli connection delete "$ssid" 2>/dev/null || true
            exit 1
          fi
        else
          echo ""
          echo "Failed to create connection for '$ssid'"
          exit 1
        fi
      '';
    })
  ];

  # systemd-resolved for DNS (Tor DNS port is configured in tor-proxy.nix)
  services.resolved = {
    enable = true;
    dnssec = "false";
    extraConfig = ''
      # Use Tor's DNS port once transparent proxy is active
      DNS=127.0.0.1:5353
      FallbackDNS=
      DNSOverTLS=no
      DNSSEC=no
      Cache=no
    '';
  };
}
