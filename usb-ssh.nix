{ config, lib, pkgs, ... }:

{
  boot.kernelModules = [ "g_ether" ];

  systemd.services.usb-gadget-ethernet = {
    description = "USB Gadget Ethernet";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-devices-platform-usb0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "usb-gadget-setup" ''
        # Wait for usb0 interface
        for i in $(seq 1 30); do
          if ${pkgs.iproute2}/bin/ip link show usb0 >/dev/null 2>&1; then
            break
          fi
          sleep 0.5
        done
        ${pkgs.iproute2}/bin/ip addr add 192.168.64.2/24 dev usb0
        ${pkgs.iproute2}/bin/ip link set usb0 up
      '';
    };
  };
}
