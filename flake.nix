{
  description = "Read `variables:` blocks out of YAML files into a flat attrset of strings";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Main entry point:
      #   yamlVars = inputs.nix-yaml-vars.lib { inherit pkgs; };
      lib =
        {
          pkgs,
          lib ? pkgs.lib,
          defaultAttrPath ? [ "variables" ],
        }:
        import ./. { inherit pkgs lib defaultAttrPath; };

      checks = forAllSystems (pkgs: {
        tests = import ./tests.nix { inherit pkgs; };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
