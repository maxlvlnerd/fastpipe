{
  description = "Rust-Nix";

  inputs = {
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    rust-overlay.url = "github:oxalica/rust-overlay";
    crate2nix.url = "github:nix-community/crate2nix";

    # Development

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-trusted-public-keys = "eigenvalue.cachix.org-1:ykerQDDa55PGxU25CETy9wF6uVDpadGGXYrFNJA3TUs=";
    extra-substituters = "https://eigenvalue.cachix.org";
    allow-import-from-derivation = true;
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    rust-overlay,
    crate2nix,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
      ];

      imports = [
        ./nix/rust-overlay/flake-module.nix
        ./nix/devshell/flake-module.nix
      ];

      perSystem = {
        system,
        pkgs,
        lib,
        inputs',
        ...
      }: let
        # If you dislike IFD, you can also generate it with `crate2nix generate`
        # on each dependency change and import it here with `import ./Cargo.nix`.
        customBuildRustCrateForPkgs = pkgs:
          pkgs.buildRustCrate.override {
            defaultCrateOverrides =
              pkgs.defaultCrateOverrides
              // {
                libspa-sys = attrs: {
                  buildInputs = [pkgs.pkg-config pkgs.pipewire pkgs.rustPlatform.bindgenHook];
                };
                pipewire-sys = attrs: {
                  buildInputs = [pkgs.pkg-config pkgs.pipewire pkgs.rustPlatform.bindgenHook];
                };
                libspa = _: {
                  buildInputs = [pkgs.pkg-config pkgs.pipewire];
                };
              };
          };
        cargoNix =
          pkgs.callPackage (inputs.crate2nix.tools.${system}.generatedCargoNix {
            name = "fastpipe";
            src = ./.;
          }) {
            buildRustCrateForPkgs = customBuildRustCrateForPkgs;
          };
      in rec {
        checks = {
          fastpipe = cargoNix.rootCrate.build.override {
            runTests = true;
          };
        };

        packages = {
          fastpipe = cargoNix.rootCrate.build;
          default = packages.fastpipe;

          inherit (pkgs) rust-toolchain;
        };
      };
    };
}
