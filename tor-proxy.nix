{ config, lib, pkgs, ... }:

# Design: Network and Tor Initialization Flow
# ============================================
# 1. Boot: USB ethernet (192.168.64.0/24) provides local connectivity to macOS host
#    - No internet access at this point
#    - User can SSH in via: ssh nixos@192.168.64.2
#
# 2. User runs `wifi-setup` to connect to WiFi
#    - Board gets internet connectivity via wlan0
#
# 3. wifi-online.service detects WiFi connectivity
#    - Monitors for wlan0 to have a default route and internet access
#    - Only triggers when actual internet is available (not just USB ethernet)
#
# 4. systemd-timesyncd starts (requires: wifi-online)
#    - Syncs system clock via NTP
#    - Has DIRECT internet access (bypasses Tor) - this is intentional
#    - Tor certificates require accurate time to validate
#
# 5. tor.service starts (requires: timesyncd completed successfully)
#    - Establishes Tor circuits
#    - Without correct time, Tor would fail certificate validation
#
# 6. tor-transparent-proxy.service activates (requires: tor running)
#    - Sets up iptables rules to force ALL traffic through Tor
#    - Only tor and systemd-timesync users can access internet directly
#    - All other processes are forced through Tor transparent proxy
#
# Security Model:
# - Only two processes can access internet directly: timesyncd and tor
# - All other traffic is forced through Tor or rejected
# - This prevents any application from leaking real IP

{
  # Time sync - critical for Tor certificate validation
  services.timesyncd.enable = true;

  # wifi-online.service: Detects when WiFi has internet connectivity
  # This is the trigger for the entire Tor initialization chain
  systemd.services.wifi-online = {
    description = "Wait for WiFi Internet Connectivity";
    wantedBy = [ "multi-user.target" ];
    after = [ "NetworkManager.service" ];
    # When wifi-online completes, start the time sync chain
    wants = [ "systemd-timesyncd.service" "time-synced.service" ];
    before = [ "systemd-timesyncd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Don't fail the boot if WiFi isn't connected yet
      ExecStart = pkgs.writeShellScript "wait-for-wifi" ''
        echo "Waiting for WiFi internet connectivity..."
        echo "Run 'wifi-setup' to connect to a WiFi network."

        # Wait for wlan0 to have a default route (indicates WiFi connected with DHCP)
        while true; do
          if ${pkgs.iproute2}/bin/ip route show dev wlan0 2>/dev/null | grep -q "default"; then
            echo "WiFi connected, checking internet access..."
            # Verify actual internet connectivity (not just local network)
            if ${pkgs.iputils}/bin/ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
              echo "Internet connectivity confirmed via WiFi"
              break
            fi
          fi
          sleep 5
        done
      '';
    };
  };

  # Override timesyncd to wait for WiFi connectivity
  systemd.services.systemd-timesyncd = {
    after = [ "wifi-online.service" ];
    requires = [ "wifi-online.service" ];
  };

  # time-synced.service: Waits for actual NTP sync (not just daemon start)
  # systemd-timesyncd is a daemon that starts before sync completes
  systemd.services.time-synced = {
    description = "Wait for Time Synchronization";
    after = [ "systemd-timesyncd.service" ];
    requires = [ "systemd-timesyncd.service" ];
    # When time-synced completes, start Tor
    wants = [ "tor.service" ];
    before = [ "tor.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "wait-for-time-sync" ''
        echo "Waiting for NTP time synchronization..."
        # Wait until timedatectl shows synchronized
        while ! ${pkgs.systemd}/bin/timedatectl show -p NTPSynchronized --value | grep -q "yes"; do
          sleep 1
        done
        echo "Time synchronized: $(date)"
      '';
    };
  };

  # Tor must wait for time to be ACTUALLY synchronized
  systemd.services.tor = {
    after = [ "time-synced.service" "wifi-online.service" ];
    requires = [ "wifi-online.service" "time-synced.service" ];
    # When tor starts, trigger the transparent proxy setup
    wants = [ "tor-transparent-proxy.service" ];
  };

  # Disable NetworkManager-wait-online to avoid boot delays
  # (USB ethernet is up immediately, but that's not "online" for our purposes)
  systemd.services.NetworkManager-wait-online.enable = false;

  services.tor = {
    enable = true;
    client.enable = true;  # Enables SOCKS port

    settings = {
      ControlPort = 9051;
      CookieAuthentication = true;

      # SOCKSPort is configured by client.enable = true (127.0.0.1:9050)

      TransPort = [
        { addr = "127.0.0.1"; port = 9040; }
      ];

      DNSPort = [
        { addr = "127.0.0.1"; port = 5353; }
      ];

      AutomapHostsOnResolve = true;
      AutomapHostsSuffixes = [ ".onion" ".exit" ];

      VirtualAddrNetworkIPv4 = "10.192.0.0/10";

      Log = "notice stdout";

      DataDirectory = "/var/lib/tor";

      ExitPolicy = [ "reject *:*" ];

      DisableNetwork = false;

      SocksTimeout = 120;

      CircuitBuildTimeout = 30;

      ExitNodes = "{us}";

      StrictNodes = false;

      UseBridges = false;
    };
  };

  # Transparent proxy setup - forces all traffic through Tor
  # Only activates after Tor is confirmed running
  systemd.services.tor-transparent-proxy = {
    description = "Tor Transparent Proxy Setup";
    wantedBy = [ "multi-user.target" ];
    after = [ "tor.service" ];
    requires = [ "tor.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "setup-tor-proxy" ''
        echo "Waiting for Tor to be ready..."
        timeout=60
        while [ $timeout -gt 0 ] && ! ${pkgs.netcat}/bin/nc -z 127.0.0.1 9040; do
          sleep 1
          timeout=$((timeout - 1))
        done

        if [ $timeout -eq 0 ]; then
          echo "ERROR: Tor TransPort not available within 60 seconds"
          exit 1
        fi

        echo "Tor is running, configuring transparent proxy..."

        # Flush existing rules
        ${pkgs.iptables}/bin/iptables -t nat -F
        ${pkgs.iptables}/bin/iptables -t filter -F OUTPUT

        # === NAT table rules (transparent proxy redirection) ===

        # Allow Tor daemon to connect directly (CRITICAL - prevents loops)
        ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -m owner --uid-owner tor -j RETURN

        # Allow timesyncd to connect directly (needs NTP for accurate time)
        ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -m owner --uid-owner systemd-timesync -j RETURN

        # Don't redirect local/private network traffic
        ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -d 127.0.0.0/8 -j RETURN
        ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -d 192.168.0.0/16 -j RETURN
        ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -d 10.0.0.0/8 -j RETURN
        ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -d 172.16.0.0/12 -j RETURN

        # Redirect DNS to Tor's DNS port
        ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-port 5353
        ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-port 5353

        # Redirect all other TCP to Tor's transparent proxy port
        ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-port 9040

        # === FILTER table rules (block non-Tor traffic) ===

        # Allow Tor daemon direct internet access
        ${pkgs.iptables}/bin/iptables -A OUTPUT -m owner --uid-owner tor -j ACCEPT

        # Allow timesyncd direct internet access (NTP)
        ${pkgs.iptables}/bin/iptables -A OUTPUT -m owner --uid-owner systemd-timesync -j ACCEPT

        # Allow established connections (for redirected traffic)
        ${pkgs.iptables}/bin/iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

        # Allow loopback
        ${pkgs.iptables}/bin/iptables -A OUTPUT -o lo -j ACCEPT

        # Allow local networks (USB ethernet, etc.)
        ${pkgs.iptables}/bin/iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT

        # Reject everything else (prevents leaks)
        ${pkgs.iptables}/bin/iptables -A OUTPUT -j REJECT

        echo "Transparent proxy configured - all traffic now routed through Tor"
      '';
      ExecStop = pkgs.writeShellScript "cleanup-tor-proxy" ''
        ${pkgs.iptables}/bin/iptables -t nat -F
        ${pkgs.iptables}/bin/iptables -t filter -F OUTPUT
        echo "Transparent proxy rules cleared"
      '';
    };
  };

  # Connectivity check - verifies Tor is working correctly
  systemd.services.tor-connectivity-check = {
    description = "Verify Tor Connectivity";
    wantedBy = [ "multi-user.target" ];
    after = [ "tor-transparent-proxy.service" ];
    requires = [ "tor-transparent-proxy.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "check-tor" ''
        echo "Waiting for Tor circuit establishment..."
        sleep 15

        echo "Checking Tor connectivity..."

        # Test SOCKS proxy
        if ${pkgs.curl}/bin/curl --socks5 127.0.0.1:9050 -s --max-time 30 "https://check.torproject.org/api/ip" | ${pkgs.jq}/bin/jq -e '.IsTor == true' >/dev/null; then
          echo "[OK] SOCKS proxy working"
          IP=$(${pkgs.curl}/bin/curl --socks5 127.0.0.1:9050 -s --max-time 30 "https://icanhazip.com" 2>/dev/null || echo "unknown")
          echo "     Exit IP: $IP"
        else
          echo "[FAIL] SOCKS proxy not working"
        fi

        # Test transparent proxy
        if ${pkgs.curl}/bin/curl -s --max-time 30 "https://check.torproject.org/api/ip" | ${pkgs.jq}/bin/jq -e '.IsTor == true' >/dev/null; then
          echo "[OK] Transparent proxy working"
        else
          echo "[FAIL] Transparent proxy not working - traffic may be leaking!"
        fi
      '';
    };
  };

  environment.systemPackages = with pkgs; [
    tor
    curl
    jq
    netcat
    iptables
  ];

  networking.firewall = {
    allowedTCPPorts = [ 9050 9051 ];
    extraCommands = ''
      # Allow Tor ports on INPUT
      iptables -A INPUT -p tcp --dport 9050 -j ACCEPT
      iptables -A INPUT -p tcp --dport 9051 -j ACCEPT
      iptables -A INPUT -p tcp --dport 5353 -j ACCEPT
      iptables -A INPUT -p udp --dport 5353 -j ACCEPT
    '';
  };
}
