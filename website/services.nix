{ nixpkgs, pkgs, modules, inputs, ... }:
{
  port ? 3000,
  branch ? "master",
  secretsFolder ? ./secrets,
  secretsPath ? "/home/hello-world-app/.config/hello-world-app/environment",
  sopsKey ? "/home/hello-world-app/.config/hello-world-app/keys.txt",
}: let
  inherit (pkgs.lib) concatStringsSep;

  serviceSuffix = "-${branch}";
  secretsSuffix = if builtins.elem branch [ "master" "develop" ] then serviceSuffix else "-pr";
  secrets = "${secretsFolder}/secrets${secretsSuffix}.env";

  secretsPathWithSuffix = "${secretsPath}${serviceSuffix}";

  nixosSystem = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = modules ++ [{
      services.hello-world-app = {
        enable = true;
        secretsFile = secretsPathWithSuffix;
        inherit port;
      };
      systemd.services.hello-world-app.preStart = ''
        while ! ( systemctl is-active network-online.target > /dev/null ); do sleep 1; done
      '';
      systemd.services.hello-world-app = {
        after = [ "sops-nix${serviceSuffix}.service" ];
        bindsTo = [ "sops-nix${serviceSuffix}.service" ];
      };
    }];
  };

  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      inputs.sops-nix.homeManagerModule
      {
        home = {
          username = "hello-world";
          homeDirectory = "/home/hello-world";
          stateVersion = "22.11";
        };
        sops = {
          defaultSopsFile = secrets;
          age.keyFile = sopsKey;
          defaultSopsFormat = "dotenv";
          defaultSymlinkPath = "%r/.secrets${serviceSuffix}";
          defaultSecretsMountPoint = "%r/.secrets${serviceSuffix}.d";
          secrets.hello-world-app-secrets.path = secretsPathWithSuffix;
        };
      }
    ];
  };

  serviceNames = [ "hello-world-app" "sops-nix" ];

  mkService = name: if name == "sops-nix" then sopsService
    else pkgs.writeText "${name}.service" nixosSystem.config.systemd.units."${name}.service".text;

  sopsExecStart = homeConfiguration.config.systemd.user.services.sops-nix.Service.ExecStart;
  sopsService = pkgs.writeText "$sops-nix.service" ''
    [Service]
    Type=oneshot
    ExecStart=${sopsExecStart}
    RemainAfterExit=true

    [Install]
    WantedBy=default.target
  '';

  copyServices = concatStringsSep "\n" (map (name: let serviceName = name + serviceSuffix; in ''
    rm -f -- "$HOME/.config/systemd/user/${serviceName}.service" "$HOME/.config/systemd/user/default.target.wants/${serviceName}.service"
    ln -s ${mkService name} "$HOME/.config/systemd/user/${serviceName}.service"
    ln -s "$HOME/.config/systemd/user/${serviceName}.service" "$HOME/.config/systemd/user/default.target.wants"
  '') serviceNames);

  activate = pkgs.writeShellScriptBin "activate" ''
    set -euo pipefail
    export XDG_RUNTIME_DIR="/run/user/$UID"
    mkdir -p "$HOME/.config/systemd/user/default.target.wants"
    ${copyServices}
    systemctl --user daemon-reload
    systemctl --user restart ${concatStringsSep " " serviceNames}

    # Check if services started
    retry_count=0
    while [[ "$retry_count" -lt 5 ]]; do
      set +e
      ${isActive} > /dev/null && exit 0
      set -e
      retry_count=$((retry_count+1))
      sleep 5
    done
    # if services didn't start exit with failure
    exit 1
  '';
  isActive = concatStringsSep " > /dev/null && " (map (name: "systemctl --user is-active ${name}") serviceNames);

  removeServices = concatStringsSep "\n" (map (name: let serviceName = name + serviceSuffix; in ''
    set +e
    systemctl --user stop ${serviceName}.service
    systemctl --user disable ${serviceName}.service
    set -e
    rm -f -- "$HOME/.config/systemd/user/${serviceName}.service" "$HOME/.config/systemd/user/default.target.wants/${serviceName}.service"
  '') serviceNames);

  deactivate = pkgs.writeShellScriptBin "deactivate" ''
    set -euo pipefail
    export XDG_RUNTIME_DIR="/run/user/$UID"
    ${removeServices}
    systemctl --user daemon-reload
    systemctl --user reset-failed
    rm -f ${secretsPathWithSuffix}
  '';

in pkgs.buildEnv {
  name = "hello-world-app-service";
  paths = [ activate deactivate ];
}
