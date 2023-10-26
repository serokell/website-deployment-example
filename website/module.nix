{ self, ... }@ inputs:
{ config, pkgs, lib, ... }:
let
  inherit (lib) mkEnableOption mkOption mkIf types mkMerge;
  cfg = config.services.hello-world-app;
in
{
  options.services.hello-world-app = {
    enable = lib.mkEnableOption "hello-world-app";
    package = mkOption {
      type = types.path;
      default = self.packages.x86_64-linux.hello-world-app;
      description = ''
        Path to the package
      '';
    };
    port = mkOption {
      type = types.port;
      default = 3000;
      description = ''
        Port of the site
      '';
    };
    secretsFile = mkOption {
      type = types.path;
      description = ''
        Path to the secrets file on the deployment server
      '';
    };
    
  };
  config = mkIf cfg.enable {
    systemd.services.hello-world-app = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = [
        "${cfg.package}/bin/hello-world-app"
        cfg.secretsFile
      ];
      serviceConfig.EnvironmentFile = cfg.secretsFile;
      environment = {
        PORT = toString cfg.port;
      };
      script = ''
        ${cfg.package}/bin/hello-world-app
      '';
    };
  };
      # services.postgresql = {
      #   enable = true;
      #   package = pkgs.postgresql_14;
      #   port = dbPort;
      #   ensureDatabases = [ dbName ];
      #   ensureUsers = [
      #     { name = dbUser;
      #       ensurePermissions = {
      #         "DATABASE \"${dbName}\"" = "ALL PRIVILEGES";
      #       };
      #     }
      #   ];
      #   authentication = ''
      #     host  all  ${dbUser}  localhost  trust
      #   '';
      # };
    # })
}
