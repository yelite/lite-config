# lite-system

`lite-system` provides a convinient way to build NixOS, nix-darwin and Home Manager configurations.

A minimal example:

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    lite-system.url = "github:yelite/lite-system";
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} ({inputs, ...}: {
      imports = [
        inputs.lite-system.flakeModule
      ];

      config.lite-system = {
        # Configure the nixpkgs that is used in all configurations created by `lite-system`.
        nixpkgs = {
          config = {
            allowUnfree = true;
          };
          overlays = [
            (import ./overlay)
          ];
        };

        # The system module will be imported for all host configurations.
        systemModule = ./system;
        # The home module is a Home Manager module, used by all host configurations.
        homeModule = ./home;
        # This directory contains per-host system module.
        hostModuleDir = ./hosts;

        hosts = {
          # This generates `nixosConfigurations.my-desktop` with NixOS module
          # `./system`, `./hosts/my-desktop` and Home Manager module `./home`.
          my-desktop = {
            system = "x86_64-linux";
          };

          # This generates `darwinConfigurations.my-macbook` with nix-darwin module
          # `./system`, `./hosts/my-desktop` and Home Manager module `./home`.
          #
          # Note that `./system` module is used in both NixOS and nix-darwin configurations.
          # A `hostPlatform` special arg is added to both system modules
          # and home manager modules, enabling conditional configuration based on
          # the system type.
          my-macbook = {
            system = "aarch64-darwin";
          };
        };
      };
    });
}
```

# Why?

## Why flake?

From [https://nixos.wiki/wiki/Flakes](),

> Flake improves reproducibility, composability and usability in the Nix ecosystem.

When it comes to building system configurations, the most significant advantage
offered by flakes is reproducibility. By utilizing flakes, it's ensured that environments
across all systems achieve the highest degree of consistency possible.

## Why flake module (flake-parts)?

From [https://github.com/hercules-ci/flake-parts#why-modules](),

> Flakes are configuration. The module system lets you refactor configuration into modules that can be shared.
> It reduces the proliferation of custom Nix glue code, similar to what the module system has done for NixOS configurations.

While the flexibility provided by flake-parts may not provide significant advantages for
creating system configurations, it will shine if there is need to add other kinds of things
into the same flake.

## Why lite-system?

WIP
