toplevel @ {
  inputs,
  lib,
  withSystem,
  ...
}: let
  inherit
    (builtins)
    listToAttrs
    attrNames
    attrValues
    foldl'
    length
    filter
    ;
  inherit
    (lib)
    mkIf
    mkOption
    mkDefault
    mkMerge
    mapAttrs
    types
    recursiveUpdateUntil
    isDerivation
    literalExpression
    ;
  cfg = toplevel.config.lite-config;

  overlayType = types.uniq (types.functionTo (types.functionTo (types.lazyAttrsOf types.unspecified)));
  nixpkgsOptionType = types.submodule {
    options = {
      nixpkgs = mkOption {
        type = types.path;
        default = inputs.nixpkgs;
        defaultText = literalExpression "inputs.nixpkgs";
        description = ''
          The nixpkgs flake to use.

          This option needs to set if the nixpkgs that you want to use is under a different name
          in flake inputs.
        '';
      };
      config = mkOption {
        default = {};
        type = types.attrs;
        description = ''
          The configuration of the Nix Packages collection.
        '';
        example =
          literalExpression
          ''
            { allowUnfree = true; }
          '';
      };
      perSystemOverrides = mkOption {
        default = {};
        type = types.attrsOf (types.submodule {
          options = {
            nixpkgs = mkOption {
              type = types.path;
              default = inputs.nixpkgs;
              defaultText = literalExpression "inputs.nixpkgs";
              description = ''
                The nixpkgs flake to use for this system.
              '';
            };
            config = mkOption {
              default = {};
              type = types.attrs;
              description = ''
                The configuration of the Nix Packages collection for this system.
              '';
              example =
                literalExpression
                ''
                  { allowUnfree = true; }
                '';
            };
          };
        });
        description = ''
          Overrides for the nixpkgs used in a particular system. Useful for choosing
          a pinned nixpkgs commit for some platform.

          It's not suggested to keep using a pinned nixpkgs for a system in the long run.
          Doing so will only deviate environments on your different machines, eventually
          making the system with pinned nixpkgs failed to build.
        '';
        example =
          literalExpression
          ''
            {
              "aarch64-darwin" = inputs.nixpkgs-darwin;
            }
          '';
      };
      overlays = mkOption {
        default = [];
        type = types.listOf overlayType;
        description = ''
          List of overlays to use with the Nix Packages collection.
        '';
        example =
          literalExpression
          ''
            [
              inputs.fenix.overlays.default
            ]
          '';
      };
      exportOverlayPackages = mkOption {
        default = true;
        type = types.bool;
        description = ''
          Whether packages in the overlays should be exported as packages.
        '';
      };
      setPerSystemPkgs = mkOption {
        default = true;
        type = types.bool;
        description = ''
          Whether the nixpkgs used in lite-config should also be set as the `pkgs` arg for
          the perSystem module.
        '';
      };
    };
  };
  hostConfigType = types.submodule {
    options = {
      system = mkOption {
        type = types.str;
        description = ''
          The system of the host.
        '';
        example =
          literalExpression
          ''
            "x86_64-linux"
          '';
      };
      hostModule = mkOption {
        type = types.nullOr types.deferredModule;
        default = null;
        description = ''
          The host module that is imported by this host.
          If null, the module at "''${{option}`lite-config.hostModuleDir`}/''${hostName}"
          will be used as hostModule.
        '';
      };
    };
  };
  builderOptionType = types.submodule {
    options = {
      darwin = mkOption {
        type = types.functionTo types.attrs;
        default = inputs.nix-darwin.lib.darwinSystem;
        defaultText = literalExpression ''
          inputs.nix-darwin.lib.darwinSystem
        '';
        description = ''
          The builder function for darwin system. This option should be set
          if the `nix-darwin` flake is under a different name in flake inputs.
        '';
      };
    };
  };
  liteConfigType = types.submodule {
    options = {
      nixpkgs = mkOption {
        type = nixpkgsOptionType;
        default = {};
        description = ''
          Config about the nixpkgs used by lite-config.
          All configurations produced by lite-config will use the nixpkgs specified in this option.
        '';
      };

      hosts = mkOption {
        type = types.attrsOf hostConfigType;
        default = {};
        description = ''
          Host configurations.
        '';
      };

      systemModules = mkOption {
        type = types.listOf types.deferredModule;
        default = [];
        description = ''
          Shared system modules (NixOS or nix-darwin) to be imported by all hosts.
        '';
      };

      homeModules = mkOption {
        type = types.listOf types.deferredModule;
        default = [];
        description = ''
          Home manager modules to be imported by all hosts.
        '';
      };

      hostModuleDir = mkOption {
        type = types.path;
        description = ''
          The directory that contains host modules. Module at
          `''${hostMouduleDir}/''${hostName}` will be imported in
          the configuration of host `hostName` by default.

          The host module used by a host can be overridden in
          {option}`lite-config.hosts.<hostName>.hostModule`.
        '';
      };

      builder = mkOption {
        type = builderOptionType;
        default = {};
        description = ''
          Options about system configuration builder.

          By default, the builder for MacOS is `inputs.nix-darwin.lib.darwinSystem`
          and the builder for NixOS is {option}`lite-config.nixpkgs.nixpkgs.lib.nixosSystem`.
        '';
      };

      homeManagerFlake = mkOption {
        type = types.path;
        default = inputs.home-manager;
        defaultText = literalExpression ''
          inputs.home-manager
        '';
        description = ''
          The home-manager flake to use.
          This should be set if home-manager isn't named as `home-manager` in flake inputs.

          This has no effect if {option}`lite-config.homeModules` is empty.
        '';
      };

      homeConfigurations = mkOption {
        type = types.attrsOf types.deferredModule;
        default = {};
        description = ''
          Per-user Home Manager module used for exporting homeConfigurations to be used
          by systems other than NixOS and nix-darwin.

          The exported homeConfigurations will import `lite-config.homeModules` and the value of
          this attrset.

          This has no effect if {option}`lite-config.homeModules` is empty.
        '';
        example =
          literalExpression
          ''
            {
              joe = {
                myConfig = {
                  neovim.enable = true;
                };
              };
            }
          '';
      };
    };
  };

  useHomeManager = cfg.homeModules != [] || cfg.homeConfigurations != {};

  makeSystemConfig = hostName: hostConfig:
    withSystem hostConfig.system ({liteConfigPkgs, ...}: let
      hostPlatform = liteConfigPkgs.stdenv.hostPlatform;
      hostModule =
        if hostConfig.hostModule == null
        then "${cfg.hostModuleDir}/${hostName}"
        else hostConfig.hostModule;
      homeManagerSystemModule =
        if hostPlatform.isLinux
        then cfg.homeManagerFlake.nixosModules.default
        else if hostPlatform.isDarwin
        then cfg.homeManagerFlake.darwinModules.default
        else throw "System type ${hostPlatform.system} not supported.";
      specialArgs = {
        inherit inputs hostPlatform;
      };
      modules =
        [
          hostModule
          {
            _file = ./.;
            nixpkgs.pkgs = liteConfigPkgs;
            networking.hostName = hostName;
          }
        ]
        ++ cfg.systemModules
        ++ lib.optionals useHomeManager [
          homeManagerSystemModule
          {
            _file = ./.;
            home-manager = {
              sharedModules = cfg.homeModules;
              useGlobalPkgs = true;
              extraSpecialArgs = specialArgs;
            };
          }
        ];
      builderArgs = {
        inherit specialArgs modules;
      };
    in
      if hostPlatform.isLinux
      then {
        nixosConfigurations.${hostName} = cfg.nixpkgs.nixpkgs.lib.nixosSystem builderArgs;
      }
      else if hostPlatform.isDarwin
      then {darwinConfigurations.${hostName} = cfg.builder.darwin builderArgs;}
      else throw "System type ${hostPlatform.system} not supported.");
  systemAttrset = let
    # Merge the first two levels
    mergeSysConfig = a: b: recursiveUpdateUntil (path: _: _: (length path) > 2) a b;
    sysConfigAttrsets = attrValues (mapAttrs makeSystemConfig cfg.hosts);
  in
    foldl' mergeSysConfig {} sysConfigAttrsets;

  mkHomeConfiguration = pkgs: username: module:
    cfg.homeManagerFlake.lib.homeManagerConfiguration {
      inherit pkgs;
      modules =
        [
          module
          ({config, ...}: let
            hostPlatform = pkgs.stdenv.hostPlatform;
            defaultHome =
              if hostPlatform.isLinux
              then "/home/${config.home.username}"
              else if hostPlatform.isDarwin
              then "/Users/${config.home.username}"
              else throw "System type ${hostPlatform.system} not supported.";
          in {
            _file = ./.;
            home.username = mkDefault username;
            home.homeDirectory = mkDefault defaultHome;
          })
        ]
        ++ cfg.homeModules;

      extraSpecialArgs = {
        inherit inputs;
        hostPlatform = pkgs.stdenv.hostPlatform;
      };
    };
  createHomeConfigurations = pkgs:
    pkgs.stdenv.mkDerivation {
      name = "homeConfigurations";
      version = "1.0";
      nobuildPhase = ''
        echo
        echo "This derivation is a dummy package to group homeConfigurations under the flake outputs."
        echo "It is not meant to be built, aborting";
        echo
        exit 1
      '';
      passthru = mapAttrs (mkHomeConfiguration pkgs) cfg.homeConfigurations;
    };
in {
  options = {
    lite-config = mkOption {
      type = liteConfigType;
      default = {};
      description = ''
        The config for lite-config.
      '';
    };
  };

  config = {
    # Setting the systems to cover all configured hosts
    systems = lib.unique (attrValues (mapAttrs (_: v: v.system) cfg.hosts));

    flake = systemAttrset;

    perSystem = {
      system,
      liteConfigPkgs,
      ...
    }: {
      _file = ./.;
      config = let
        systemNixpkgs = cfg.nixpkgs.perSystemOverrides.${system} or cfg.nixpkgs;
        selectedPkgs = import systemNixpkgs.nixpkgs {
          inherit system;
          overlays = cfg.nixpkgs.overlays;
          config = cfg.nixpkgs.config;
        };
      in {
        # Make this OptionDefault so that users are able to override this pkg.
        _module.args.liteConfigPkgs = lib.mkOptionDefault selectedPkgs;

        _module.args.pkgs = lib.mkIf cfg.nixpkgs.setPerSystemPkgs liteConfigPkgs;

        packages = let
          overlayPackages = let
            overlayFn = lib.composeManyExtensions liteConfigPkgs.overlays;
            overlayPackageNames =
              # Here we use the final pkgs as both prev and final arg for the overlay function.
              # This should be fine because we only care about attr names.
              attrNames (overlayFn liteConfigPkgs liteConfigPkgs);
            overlayPackageEntries =
              map (name: {
                inherit name;
                value = liteConfigPkgs.${name} or null;
              })
              overlayPackageNames;
            # Some overlay provides non-derivation at the top level, which
            # breaks `nix flake show`. Those packages are usually not interesting
            # from system configuration's perspective. Therefore they are filtered
            # out.
            validOverlayPackageEntries = filter (e: isDerivation e.value) overlayPackageEntries;
          in
            listToAttrs validOverlayPackageEntries;

          homeManagerPackages = {
            home-manager = cfg.homeManagerFlake.packages.${system}.default;
            homeConfigurations = createHomeConfigurations liteConfigPkgs;
          };
        in
          mkMerge [
            (mkIf cfg.nixpkgs.exportOverlayPackages overlayPackages)
            (mkIf useHomeManager homeManagerPackages)
          ];
      };
    };
  };
}
