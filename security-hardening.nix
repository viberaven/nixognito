{ config, lib, pkgs, ... }:

{
  networking.firewall = {
    enable = true;

    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ ];

    # NOTE: OUTPUT firewall rules are managed by tor-transparent-proxy.service
    # in tor-proxy.nix AFTER Tor is running. This prevents boot deadlock.
    extraCommands = '''';
    extraStopCommands = '''';
  };

  systemd.services.network-lockdown = {
    description = "Network lockdown and monitoring service";
    wantedBy = [ "multi-user.target" ];
    after = [ "tor.service" "NetworkManager.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeScript "network-lockdown" ''
        #!${pkgs.bash}/bin/bash

        echo "Enabling network lockdown..."

        # Disable IPv6 to prevent leaks
        echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
        echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6

        # Disable ICMP redirects
        echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects
        echo 0 > /proc/sys/net/ipv4/conf/default/accept_redirects

        # Disable source routing
        echo 0 > /proc/sys/net/ipv4/conf/all/accept_source_route
        echo 0 > /proc/sys/net/ipv4/conf/default/accept_source_route

        # Enable reverse path filtering
        echo 1 > /proc/sys/net/ipv4/conf/all/rp_filter
        echo 1 > /proc/sys/net/ipv4/conf/default/rp_filter

        # Log martian packets
        echo 1 > /proc/sys/net/ipv4/conf/all/log_martians

        # Ignore ICMP ping requests
        echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all

        # Disable send_redirects
        echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects
        echo 0 > /proc/sys/net/ipv4/conf/default/send_redirects

        echo "Network lockdown completed"
      '';
    };
  };

  systemd.services.network-leak-check = {
    description = "Check for network leaks";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeScript "leak-check" ''
        #!${pkgs.bash}/bin/bash
        # Check for DNS leaks
        if ${pkgs.netcat}/bin/nc -z 8.8.8.8 53 2>/dev/null; then
          echo "WARNING: DNS leak detected!"
          logger -t network-lockdown "DNS leak detected - direct connection to 8.8.8.8:53"
        fi

        # Check for HTTP leaks
        if ${pkgs.netcat}/bin/nc -z 1.1.1.1 80 2>/dev/null; then
          echo "WARNING: HTTP leak detected!"
          logger -t network-lockdown "HTTP leak detected - direct connection to 1.1.1.1:80"
        fi
      '';
    };
  };

  systemd.timers.network-leak-check = {
    description = "Timer for network leak detection";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
    };
  };

  systemd.services.traffic-monitor = {
    description = "Monitor network traffic for leaks";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeScript "traffic-monitor" ''
        #!${pkgs.bash}/bin/bash

        # Monitor network connections
        while true; do
          # Check for non-Tor connections
          SUSPICIOUS_CONNS=$(${pkgs.nettools}/bin/netstat -tupln 2>/dev/null | grep -v "127.0.0.1" | grep -v ":22" | grep -v ":905" | wc -l)

          if [ "$SUSPICIOUS_CONNS" -gt 0 ]; then
            echo "$(date): Suspicious network connections detected"
            ${pkgs.nettools}/bin/netstat -tupln | grep -v "127.0.0.1" | grep -v ":22" | grep -v ":905" | logger -t traffic-monitor
          fi

          sleep 60
        done
      '';
      Restart = "always";
      RestartSec = "10";
    };
  };

  environment.systemPackages = with pkgs; [
    iptables
    lsof
    nettools
    tcpdump
  ];

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 0;
    "net.ipv6.conf.all.forwarding" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.icmp_echo_ignore_all" = 1;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;
  };

  services.fail2ban = {
    enable = true;
    jails = {
      ssh.settings = {
        enabled = true;
        port = "22";
        filter = "sshd";
        logpath = "/var/log/auth.log";
        maxretry = 3;
        bantime = 3600;
      };
    };
  };
}
