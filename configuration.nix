# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, lib, pkgs, ... }:

with lib;

let 
	vars = import ./vars.nix;
	caddyUpgrade = ''
                @upgradable {
                                header Upgrade-Insecure-Requests 1
                                protocol http
                 }
                redir @upgradable https://{host}{uri} 308
	'';
in {
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];


  # Initial empty root password for easy login:
  users.users.root.initialHashedPassword = "";
  services.openssh.permitRootLogin = "prohibit-password";
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = vars.root_keys;
  users.users.nobody.openssh.authorizedKeys.keys = vars.nobody_keys;
  services.openssh.extraConfig = ''
  	Match User nobody
          	AllowTcpForwarding local
          	AllowAgentForwarding no
          	X11Forwarding no
          	PermitTunnel no
          	PermitOpen localhost:5001 ## ipfs api
          	ForceCommand echo 'This account can only be used for Tunneling'
  '';

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.devices = [ "/dev/sda" ];


  networking.hostName = "web-hetzner-servers-malhotra-cc"; # Define your hostname.
  networking = {
    interfaces.enp0s5.ipv6.addresses = [{
      address = "2600:3c02::f03c:93ff:feb8:2aa6";
      prefixLength = 64;
    }];
    defaultGateway6 = {
      address = "fe80::1";
      interface = "enp0s5";
    };
  };

  time.timeZone = "America/Chicago";
  environment.systemPackages = with pkgs; [
    vim 
    wget
    git
    htop

#linode
    inetutils
    mtr
    sysstat
  ];
  # for nixos compiling
  services.logind.extraConfig = ''
    RuntimeDirectorySize=2G
  '';

  services.caddy = {
    enable = true;
    package = (pkgs.callPackage ./customcaddy.nix {});

    	globalConfig = ''
      		auto_https disable_redirects
       		order cgi last
		order cache before rewrite
		#cache {
		#	ttl 15s
		#}
	'';
	email = vars.email;
	logFormat = mkForce "level INFO\n";

    virtualHosts."${last (splitString "//" (head vars.domains))}" = {
        serverAliases = vars.domains;
	extraConfig = ''
		encode zstd gzip
		${caddyUpgrade}

		reverse_proxy localhost:8080

		#cache

		import /ipns/{host}/config/Caddyfile*

	        handle_errors {
	                header -x-ipfs-path
	                @404 expression {http.error.status_code} == 404
	                handle @404 {
	                        rewrite * /404.html
	                        reverse_proxy localhost:8080
	
	                        @no not file /404.html
	                        respond @no "{http.error.status_code} {http.error.status_text}"
	                }
	
	                @other expression {http.error.status_code} != 404
	                handle @other {
	                        respond "{http.error.status_code} {http.error.status_text}"
	                }
	        }
    	'';	
    };

    virtualHosts."${vars.gatewayHost}".extraConfig = ''
	${caddyUpgrade}
	encode zstd gzip
	route {
		rate_limit {remote.ip} 100r/m 429
		reverse_proxy localhost:8080
	}
	'';


  };
  systemd.services.caddy.serviceConfig.AmbientCapabilities = "CAP_NET_BIND_SERVICE";
  systemd.services.caddy.serviceConfig = {
    Restart = mkForce "on-failure";
    RestartSec = 10;
    RestartPreventExitStatus = [ 0 1 ];
  };


  services.kubo = {
    enable = true;
    autoMount = true;
  };
  systemd.services.ipfs.postStop = mkIf config.services.kubo.autoMount ''
# After an unclean shutdown the fuse mounts at ${config.services.kubo.ipnsMountDir} and ${config.services.kubo.ipfsMountDir} are locked
umount ${config.services.kubo.ipnsMountDir} || true
umount ${config.services.kubo.ipfsMountDir} || true
  '';

  networking.firewall.allowedTCPPorts = [ 
	80 443 # caddy
	4001 # ipfs
  ];
  networking.firewall.allowedUDPPorts = [ ];













  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?
}

