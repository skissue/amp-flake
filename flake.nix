{
  description = "Unofficial Amp Desktop for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    pkgsFor = system:
      import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "amp-desktop";
        overlays = [self.overlays.default];
      };
  in {
    packages = forAllSystems (
      system: let
        pkgs = pkgsFor system;
      in {
        inherit (pkgs) amp-desktop;
        default = self.packages.${system}.amp-desktop;
      }
    );

    overlays.default = final: prev: {
      amp-desktop = final.callPackage ./package.nix {};
    };

    checks.x86_64-linux.vm = import ./vm-test.nix {
      pkgs = pkgsFor "x86_64-linux";
      inherit nixpkgs;
      amp-desktop = self.packages.x86_64-linux.amp-desktop;
    };
  };
}
