{ modulesPath, pkgs, config, ... }: {
  imports = [ "${modulesPath}/virtualisation/amazon-image.nix" ];
  ec2.hvm = true;

  users = {
    users = {
      root.openssh.authorizedKeys.keys = [ "<PUBLIC_SSH_KEY_FOR_ROOT>" ];

      hello-world = {
        group = "hello-world";
        home = "/home/hello-world";
        createHome = true;
        isNormalUser = true;
        useDefaultShell = true;
        extraGroups = [ "systemd-journal" ];
        openssh.authorizedKeys.keys = [ "<PUBLIC_SSH_KEY_FOR_DEPLOYMENT>" ];
      };
    };
    groups.hello-world = {};
  };

  nix.settings.trusted-users = [ "hello-world" ];

  # Enable lingering for hello-world user
  systemd.tmpfiles.rules = [
    "f /var/lib/systemd/linger/hello-world 644 root root"
  ];

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  services.nginx = let
    mkHost = {port, extraConfig}: pkgs.lib.recursiveUpdate {
      forceSSL = true;
      locations = {
        "/".proxyPass = "http://127.0.0.1:${toString port}";
      };
    } extraConfig;
  in {
    enable = true;
    additionalModules = with pkgs.nginxModules; [ lua develkit ];
    virtualHosts."hello-world-app.com" = mkHost {
      port = 3000;
      extraConfig.enableACME = true;
    };
    virtualHosts."sandbox.hello-world-app.com" = mkHost {
      port = 3001;
      extraConfig.useACMEHost = "sandbox.hello-world-app.com";
    };
    appendHttpConfig = let
      cert = config.security.acme.certs."sandbox.hello-world-app.com".directory;
    in ''
      server {
        listen 0.0.0.0:80;
        listen [::0]:80;
        server_name ~^(pr-([0-9]+)).sandbox.hello-world-app.com;
        location / {
          return 301 https://$host$request_uri;
        }
      }

      server {
        listen 0.0.0.0:443 http2 ssl;
        listen [::0]:443 http2 ssl;
        server_name ~^(pr-(?<pr_number>[0-9]+)).sandbox.hello-world-app.com;

        ssl_certificate ${cert}/fullchain.pem;
		    ssl_certificate_key ${cert}/key.pem;
		    ssl_trusted_certificate ${cert}/chain.pem;

        location / {
          set_by_lua_block $server_port {
            return 43000 + ngx.var.pr_number % 1000
          }
          proxy_pass http://127.0.0.1:$server_port;
        }
      }
    '';
  };

  sops.secrets.dns-provider-token = {};
  security.acme = {
    defaults.email = "contact@hello-world-app.com";
    acceptTerms = true;
    certs."sandbox.hello-world-app.com" = {
      group = "nginx";
      dnsProvider = "godaddy";
      credentialsFile = config.sops.secrets.dns-provider-token.path;
      extraDomainNames = ["*.sandbox.hello-world-app.com"];
    };
  };

  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 1d";
  };

  sops.secrets.gh-token.owner = "hello-world";
  services.cleanup = {
    enable = true;
    tokenFile = config.sops.secrets.gh-token.path;
    profiles.hello-world = {
      repo = "hello-world-app";
      user = "hewllo-world";
    };
  };

  system.stateVersion = "23.05";
}
