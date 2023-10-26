{
  inputs = {
    deploy-rs.url = "github:serokell/deploy-rs";
    nixpkgs.url = "nixpkgs/nixos-23.05";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = {self, nixpkgs, flake-utils, deploy-rs, sops-nix, ...}@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      nixosConfigurations.hello-world-server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          sops-nix.nixosModules.sops
          ./modules/cleanup.nix
          ./servers/hello-world-server.nix
        ];
      }; 
      deploy = {
        magicRollback = true;
        autoRollback = true;
        nodes.hello-world-server = {
          hostname = "hello-world-app.com";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.hello-world-server;
          };
        };
      };

      checks = deploy-rs.lib.${system}.deployChecks self.deploy;

      devShells.x86_64-linux.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          deploy-rs.packages.${system}.deploy-rs
          age
          sops
        ];
      };
    };
}
