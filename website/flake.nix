{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-23.05";
    nix-npm.url = "github:serokell/nix-npm-buildpackage";
    deploy-rs.url = "github:serokell/deploy-rs";
    sops-nix.url = "github:Mic92/sops-nix";
    home-manager = {
      url = "github:nix-community/home-manager/release-22.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-npm, deploy-rs, sops-nix, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          nix-npm.overlays.default
          (self: super: { nodejs = super.nodejs-18_x; })
        ];
      };

      nixosModules = { default = import ./module.nix inputs; };

      services = import ./services.nix {
        inherit (inputs) nixpkgs;
        inherit pkgs inputs;
        modules = [ nixosModules.default ];
      };

      nixosConfigurations.hello-world-app = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ({ config, pkgs, ... }: {
          virtualisation.vmVariant.virtualisation = {
            graphics = false;
            memorySize = 2048;
            diskSize = 4096;
            cores = 2;
          };

          networking.firewall.allowedTCPPorts = [ 3000 ];

          imports = [ self.nixosModules.default ];

          users.users.root.password = "";

          environment.etc."secrets.env".text = ''
            SECRET_VARIABLE="SOME DEFAULT SECRET VALUE FOR DEVELOPMENT"
          '';
          services.hello-world-app = {
            enable = true;
            port = 3000;
            secretsFile = "/etc/secrets.env";
          };
        })];
      };

      hello-world-app-package = pkgs.buildYarnPackage {
        name = "hello-world-app-package";
        src = builtins.path { name = "hello-world-app"; path = ./hello-world-app; };
        yarnBuild = ''
          yarn install
          yarn build
        '';
        postInstall = ''
          mv ./.next $out/
        '';
      };

      hello-world-app = pkgs.writeShellApplication {
        name = "hello-world-app";
        text = ''
          ${hello-world-app-package}/bin/yarn start -p "$PORT" ${hello-world-app-package}
          '';
        };

      mkYarnCheck = name: command:
        pkgs.runCommand "hello-world-app-${name}" {} ''
          ${hello-world-app-package}/bin/yarn run ${command}
          touch $out
        '';

      prettier-check = mkYarnCheck "prettier" "prettier --check \"pages/**/*.tsx\"";

      mkNode = {hostname ? "hello-world-app.com", script ? "activate", branch, port}: {
        inherit hostname;
        sshUser = "hello-world";
        user = "hello-world";
        profiles = {
          "hello-world-${branch}".path = deploy-rs.lib.x86_64-linux.activate.custom (services { inherit branch port; }) "$PROFILE/bin/${script}";
        };
      };

      prNumber = builtins.readFile ./pr-number;
      prNode = script: mkNode {
        inherit script;
        branch = "pr${prNumber}";
        port = 43000 + pkgs.lib.mod (pkgs.lib.toInt prNumber) 1000;
      };

    in {
      inherit nixosConfigurations nixosModules;

      packages.x86_64-linux = { inherit hello-world-app; };
      checks.x86_64-linux = { inherit prettier-check; } // deploy-rs.lib.${system}.deployChecks self.outputs.deploy;

      deploy = {
        nodes = {
          hello-world-master = mkNode {
            branch = "master";
            port = 3000;
          };
          hello-world-develop = mkNode {
            branch = "develop";
            port = 3001;
          };
          hello-world-pr = prNode "activate";
          cleanup = prNode "deactivate";
        };
      };

      devShells.x86_64-linux.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          sops
          age
          deploy-rs.packages.${system}.deploy-rs
        ];
      };
    };
}
