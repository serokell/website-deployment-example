{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkOption mkIf types mapAttrs';
  cfg = config.services.cleanup;
  cleanupConfig = types.submodule ({config, ...}: {
    options = {
      repo = mkOption {
        type = types.str;
        description = ''
          Github repository
        '';
      };
      githubOrganization = mkOption {
        type = types.str;
        default = "runtimeverification";
      };
      user = mkOption {
        type = types.str;
        description = ''
          Name of the user used to deploy services
        '';
      };
      bootTimer = mkOption {
        type = types.str;
        default = config.timer;
        description = ''
          Defines a timer relative to when the machine was booted up
        '';
      };
      timer = mkOption {
        type = types.str;
        default = "15m";
        description = ''
          Defines a timer relative to when service was last activated
        '';
      };
    };
  });
in {
  options.services.cleanup = {
    enable = mkEnableOption "cleanup";
    profiles = mkOption {
      type = types.attrsOf cleanupConfig;
      description = ''
        Attribute sets with configuration for each project, where attribute name is the name of the profile used in deploy-rs, without suffix
      '';
    };
    tokenFile = mkOption {
      type = types.path;
      description = ''
        File with Github API token with read access to pull requests
      '';
    };
  };

  config = let
    mkTimer = profileName: {user, timer, bootTimer, ...}: {
      wantedBy = [ "timers.target" ];
      unitConfig.ConditionUser = user;
      timerConfig = {
        OnBootSec = bootTimer;
        OnUnitActiveSec = timer;
        Unit = "${profileName}-cleanup.service";
      };
    };
    mkService = profileName: {repo, githubOrganization, user, ...}: {
      script = ''
        set -euo pipefail

        OPEN_PRS=$((${pkgs.curl}/bin/curl -L \
          -H "Accept: application/vnd.github+json" \
          -H "Authorization: Bearer $TOKEN"\
          -H "X-GitHub-Api-Version: 2022-11-28" \
          https://api.github.com/repos/${githubOrganization}/${repo}/pulls?state=open&per_page=100) \
          | ${pkgs.jq}/bin/jq '.[] | .number')

        [[ ! -z "$OPEN_PRS" ]] && echo "Found open pull requests with numbers: $(echo $OPEN_PRS)"

        cd /nix/var/nix/profiles/per-user/${user}/

        for n in $(ls | grep -oP '(?<=${profileName}-pr)\d+' | sort -u); do
          if [[ ! $(echo $OPEN_PRS) =~ (^| )$n($| ) ]]; then
            echo "Removing services associated with pull request nubmer $n"
            source ${profileName}-pr$n/bin/deactivate
            echo "Removing nix profile associated with pull request nubmer $n"
            rm -f /nix/var/nix/profiles/per-user/${user}/${profileName}-pr$n{,-*}
          fi
        done
      '';

      unitConfig.ConditionPathExists = [ cfg.tokenFile ];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = cfg.tokenFile;
      };
    };
  in mkIf cfg.enable {
    systemd.user.timers = mapAttrs' (name: opts: {
      name = "${name}-cleanup";
      value = mkTimer name opts;
    }) cfg.profiles;
    systemd.user.services = mapAttrs' (name: opts: {
      name = "${name}-cleanup";
      value = mkService name opts;
    }) cfg.profiles;
  };
}
