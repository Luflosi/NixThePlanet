{ config, lib, pkgs, ... }:
let
  cfg = config.services.macos-ventura;
in
{
  options.services.macos-ventura = {
    enable = lib.mkEnableOption "macos-ventura";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.macos-ventura-image;
      defaultText = "pkgs.macos-ventura-image";
      description = ''
        Which macOS-ventura-image derivation to use.
      '';
    };
    dataDir = lib.mkOption {
      default = "/var/lib/nixtheplanet-macos-ventura";
      type = lib.types.str;
    };
    vncListenAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = lib.mdDoc ''
        Address to bind VNC (Virtual Desktop) to
      '';
    };
    vncDisplayNumber = lib.mkOption {
      type = lib.types.port;
      default = 0;
      description = lib.mdDoc ''
        Port to bind VNC (Virtual Desktop) to, added to 5900, e.g 1 means the
        VNC will run on port 5901
      '';
    };
    sshListenAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = lib.mdDoc ''
        Address on which to listen for forwarding the VM port 22 to the host
      '';
    };
    sshPort = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = lib.mdDoc ''
        Port to forward on the host to VM port 22
      '';
    };
    threads = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = lib.mdDoc ''
        Number of qemu CPU threads to assign
      '';
    };
    cores = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = lib.mdDoc ''
        Number of qemu CPU cores to assign
      '';
    };
    sockets = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = lib.mdDoc ''
        Number of qemu CPU sockets to assign
      '';
    };
    mem = lib.mkOption {
      type = lib.types.str;
      default = "4G";
      description = lib.mdDoc ''
        Amount of qemu memory to assign
      '';
    };
    extraQemuFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = lib.mdDoc ''
        A list of extra flags to pass to qemu
      '';
    };
    stateless = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        If set, all state will be removed on startup of the service, removing
        all data associated with the VM, giving you a fresh VM on each service
        start.
      '';
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        Whether to open the sshPort and vncDisplayNumber on the networking.firewall
      '';
    };
    startWhenNeeded = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = lib.mdDoc ''
        If set, the VM is socket-activated; that is,
        instead of having it permanently running as a daemon,
        systemd will start it on the first incoming VNC or SSH connection.
      '';
    };
  };
  config = let
    vncPort = 5900 + cfg.vncDisplayNumber;
    run-macos = cfg.package.makeRunScript {
      diskImage = cfg.package;
      extraQemuFlags = [
        "-add-fd fd=3,set=2,opaque='vnc socket' "
        #-add-fd fd=4,set=2,opaque="rdonly:/path/to/file" \
        # -drive file=/dev/fdset/2,index=0,media=disk
        "-vnc unix:/dev/fdset/2"
      ] ++ cfg.extraQemuFlags;
      inherit (cfg) threads cores sockets mem sshListenAddr sshPort;
    };
  in lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall [ vncPort cfg.sshPort ];
    systemd = {
      services.macos-ventura = {
        preStart = lib.optionalString cfg.stateless ''
          rm -f *.qcow2
        '';
        description = "macOS Ventura";
        wantedBy = lib.optionals (!cfg.startWhenNeeded) [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe run-macos}";
          Restart = "on-failure";
          DynamicUser = true;
          StateDirectory = baseNameOf cfg.dataDir;
          WorkingDirectory = cfg.dataDir;
          Sockets = [ "macos-ventura-vnc.socket" "macos-ventura-ssh.socket" ];
        };
      };
      sockets.macos-ventura-vnc = {
        description = "macOS Ventura VNC socket";
        wantedBy = [ "sockets.target" ];
        socketConfig.ListenStream = [ "${cfg.vncListenAddr}:${toString vncPort}" ];
        socketConfig.Service = "macos-ventura.service";
      };
      /*sockets.macos-ventura-ssh = {
        description = "macOS Ventura SSH socket";
        wantedBy = [ "sockets.target" ];
        socketConfig.ListenStream = [ "${cfg.sshListenAddr}:${toString cfg.sshPort}" ];
        socketConfig.Service = "macos-ventura.service";
      };*/
    };
  };
}

