# lite-config

[![flakestry.dev](https://flakestry.dev/api/badge/flake/github/yelite/lite-config)](https://flakestry.dev/flake/github/yelite/lite-config/0.2.0)

> [!NOTE]
> lite-config is the new name of lite-system. This rename is to avoid confusion on the word 'system', 
> which is commonly used to refer to platform string, like "x86_64-linux", in context of Nix.

`lite-config` offers a convinient appraoch to build NixOS, nix-darwin and Home Manager configurations,
to create a consistent environment across different devices. It addresses common patterns
when creating personal system configurations, which includes:

1. Configure `pkgs` with overlays and config, and use it across all system configurations.
2. Build NixOS and nix-darwin configurations in a unified way.
3. Export standalone `homeConfigurations` to be used in non-NixOS Linux distributions.
4. Export packages from overlays for easy debugging.

An example:

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    lite-config.url = "github:yelite/lite-config";
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
        inputs.lite-config.flakeModule
      ];

      config.lite-config = {
        # Configure the nixpkgs that is used in all configurations created by `lite-config`.
        nixpkgs = {
          config = {
            allowUnfree = true;
          };
          overlays = [
            (import ./overlay)
          ];
        };

        # System modules will be imported for all host configurations.
        systemModules = [ ./system ];
        # Home modules are imported by Home Manager in all host configurations.
        homeModules = [ ./home ];
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

`lite-config` aims to be light weight, as the name suggests. It offers only a fundamental
framework for building flakes of system configurations. Users still need to write
NixOS (or nix-darwin) modules and home manager modules on their own, as in vanilla flake.

It requires a system module shared across all hosts, a set of per-host modules to
customize each host, and optionally a home manager module used by all hosts.

To enable the creation of unified modules for both NixOS and nix-darwin,
`lite-config` adds `hostPlatform` as a special arg to the module system.
This allows modules to be conditionally imported based on system type.

# Why?

## Why flake?

From [https://nixos.wiki/wiki/Flakes](https://nixos.wiki/wiki/Flakes),

> Flake improves reproducibility, composability and usability in the Nix ecosystem.

When it comes to building system configurations, the most significant advantage
offered by flakes is reproducibility. By utilizing flakes, it's ensured that environments
across all systems achieve the highest degree of consistency possible.

## Why flake module (flake-parts)?

From [https://github.com/hercules-ci/flake-parts#why-modules](https://github.com/hercules-ci/flake-parts#why-modules),

> Flakes are configuration. The module system lets you refactor configuration into modules that can be shared.
> It reduces the proliferation of custom Nix glue code, similar to what the module system has done for NixOS configurations.

While the flexibility provided by flake-parts may not provide significant advantages when
creating system configurations, it comes in handy when there is need to integrate
various other components within the same flake.

## Why lite-config?

The features offered by flake and flake-parts are rather primitive.
`lite-config` provides features that are commonly needed when building system configurations.
Since it's a flake module, it can also be easily customized and overridden when users
have more complex tasks to accomplish within the flake.

# Full example

```nix
{
  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} ({inputs, ...}: {
      imports = [
        inputs.lite-config.flakeModule
      ];

      config.lite-config = {
        # Configure the nixpkgs that is used in all configurations created by `lite-config`.
        nixpkgs = {
          # The nixpkgs flake to use. Default to `inputs.nixpkgs`.
          # This option needs to set if the nixpkgs that you want to use is under a
          # different name in flake inputs.
          nixpkgs = inputs.nixpkgs;
          # nixpkgs global config https://nixos.org/manual/nixpkgs/stable/#chap-packageconfig
          config = {};
          # List of overlays to use with the nixpkgs.
          overlays = [];
          # Whether packages in the overlays should be exported as packages of this flake.
          exportOverlayPackages = true;
          # Whether the nixpkgs used in lite-config should also be set as the `pkgs` arg for
          # the perSystem module.
          setPerSystemPkgs = true;
        };

        # The home-manager flake to use.
        # This should be set if home-manager isn't named as `home-manager` in flake inputs.
        # This has no effect if {option}`lite-config.homeModule` is null.
        homeManagerFlake = inputs.home-manager;

        builder = {
          # The builder function for darwin system.
          # Default to `inputs.nix-darwin.lib.darwinSystem`.
          # This option should be set if the `nix-darwin` flake is under a different name
          # in flake inputs.
          darwin = inputs.nix-darwin.lib.darwinSystem;
        };

        # System modules will be imported for all host configurations.
        systemModules = [ ./system ];
        # Home modules are imported by Home Manager in all host configurations.
        homeModules = [ ./home ];
        # This directory contains per-host system module.
        hostModuleDir = ./hosts;

        hosts = {
          host-name = {
            system = "x86_64-linux";
            # Overrides the default host module based on `hostModuleDir`.
            hostModule = ./hosts/common-desktop
          };
        };

        # Per-user Home Manager module used for exporting homeConfigurations to be used
        # by systems other than NixOS and nix-darwin.
        #
        # The exported homeConfigurations will import both `lite-config.homeModule` and the value of
        # this attrset.
        #
        # This has no effect if `lite-config.homeModule` is null.
        homeConfigurations = {
          joe = {
            myConfig = {
              neovim.enable = true;
            };
          };
        };
      };
    });
}
```

[https://github.com/yelite/system-config](https://github.com/yelite/system-config) is
a practical, real-world example on how to use `lite-config`.
