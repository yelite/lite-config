# lite-config

`lite-config` offers a convinient appraoch to build NixOS, nix-darwin and Home Manager configurations,
to create a consistent environment across different devices. It addresses common patterns
when creating personal system configurations, which includes:

1. Configure `pkgs` with overlays and config, and use it across all system configurations.
2. Build NixOS and nix-darwin configurations in a unified way.
3. Export standalone `homeConfigurations` to be used in non-NixOS Linux distributions.

An example:

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    lite-config.url = "github:gigamonster256/lite-config";

    nix-darwin.url = "github:lnl7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} ({inputs, ...}: {
      imports = [
        inputs.lite-config.flakeModule
      ];

      lite-config = {
        # Configure the nixpkgs that is used in all configurations created by `lite-config`.
        nixpkgs = {
          config.allowUnfree = true;
          overlays = builtins.attrValues import ./overlays;
        };

        # System modules will be imported for all host configurations.
        hostModules = [ ./hosts/modules ];
        # Home modules are imported by Home Manager in all host configurations.
        homeModules = [ ./home/modules ];

        hosts = {
          my-desktop = {
            system = "x86_64-linux";
            modules = [ ./hosts/my-desktop.nix ];
          };
          my-macbook = {
            system = "aarch64-darwin";
            modules = [ ./hosts/my-macbook.nix ];
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
  # TODO
}
```

[https://github.com/gigamonster256/nix-config](https://github.com/gigamonster256/nix-config) is
a practical, real-world example on how to use `lite-config`.
