# lite-system

`lite-system` offers a convinient method for building NixOS, nix-darwin and Home Manager configurations,
and creating a consistent environment across different devices. It addresses common patterns
for creating personal system configurations, which includes:

1. Configure `pkgs` and use it across all system configurations.
2. Build NixOS and nix-darwin configurations in a unified way.
3. Export standalone `homeConfigurations` for use in non-NixOS Linux distributions.
4. Export packages from overlays for easy debugging.

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
          # and home manager modules, enabling conditional confiIt offers only a fundamental framework for building flakes of system configurations. guration based on
          # the system type.
          my-macbook = {
            system = "aarch64-darwin";
          };
        };
      };
    });
}
```

`lite-system` assumes there is a system module that's imported by all hosts,
a set of per-host modules to customize each host, and optionally a home manager module
used by all hosts.

To enable the creation of unified modules for both NixOS and nix-darwin,
`lite-system` adds `hostPlatform` as special arg into the module system.
This allows modules to be conditionally imported on system type.

`lite-system` aims to be light weight, as the name suggests. It offers only a fundamental
framework for building flakes of system configurations. Users still need to write
NixOS (or nix-darwin) modules and home manager modules on their own, as in vanilla flake.

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

While the flexibility provided by flake-parts may not provide significant advantages when
creating system configurations, it comes in handy when there is need to integrate
various other components within the same flake.

## Why lite-system?

The features offered by flake and flake-parts are rather primitive.
`lite-system` provides features that are commonly needed when building system configurations.
Since it's a flake module, it can also be easily customized and overridden when users
have more complex tasks to accomplish within the flake.

# Full Example and Options
WIP
