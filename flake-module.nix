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
  cfg = toplevel.config.lite-system;

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
      overlays = mkOption {
        default = [];
        type = types.uniq (types.listOf overlayType);
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
          Whether the nixpkgs used in lite-system should also be set as the `pkgs` arg for
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
          If null, the module at "''${{option}`lite-system.hostModuleDir`}/''${hostName}"
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
  liteSystemType = types.submodule {
    options = {
      nixpkgs = mkOption {
        type = nixpkgsOptionType;
        default = {};
        description = ''
          Config about the nixpkgs used by lite-system.
          All configurations produced by lite-system will use the nixpkgs specified in this option.
        '';
      };

      hosts = mkOption {
        type = types.attrsOf hostConfigType;
        default = {};
        description = ''
          Host configurations.
        '';
      };

      systemModule = mkOption {
        type = types.nullOr types.deferredModule;
        description = ''
          The system module to be imported by all hosts.
        '';
      };

      homeModule = mkOption {
        type = types.nullOr types.deferredModule;
        default = null;
        description = ''
          The home manager module to be imported by all hosts.
        '';
      };

      hostModuleDir = mkOption {
        type = types.path;
        description = ''
          The directory that contains host modules. Module at
          `''${hostMouduleDir}/''${hostName}` will be imported in
          the configuration of host `hostName` by default.

          The host module used by a host can be overridden in
          {option}`lite-system.hosts.<hostName>.hostModule`.
        '';
      };

      builder = mkOption {
        type = builderOptionType;
        default = {};
        description = ''
          Options about system configuration builder.

          By default, the builder for MacOS is `inputs.nix-darwin.lib.darwinSystem`
          and the builder for NixOS is {option}`lite-system.nixpkgs.nixpkgs.lib.nixosSystem`.
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

          This has no effect if {option}`lite-system.homeModule` is null.
        '';
      };

      homeConfigurations = mkOption {
        type = types.attrsOf types.deferredModule;
        default = {};
        description = ''
          Per-user Home Manager module used for exporting homeConfigurations to be used
          by systems other than NixOS and nix-darwin.

          The exported homeConfigurations will import both `lite-system.homeModule` and the value of
          this attrset.

          This has no effect if {option}`lite-system.homeModule` is null.
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

  useHomeManager = cfg.homeModule != null;

  makeSystemConfig = hostName: hostConfig:
    withSystem hostConfig.system ({liteSystemPkgs, ...}: let
      hostPlatform = liteSystemPkgs.stdenv.hostPlatform;
      hostModule =
        if hostConfig.hostModule == null
        then "${cfg.hostModuleDir}/${hostName}"
        else hostConfig.hostModule;
      homeManagerSystemModule =
        if hostPlatform.isLinux
        then cfg.homeManagerFlake.nixosModule
        else if hostPlatform.isDarwin
        then cfg.homeManagerFlake.darwinModule
        else throw "System type ${hostPlatform.system} not supported.";
      specialArgs = {
        inherit inputs hostPlatform;
      };
      modules =
        [
          hostModule
          cfg.systemModule
          {
            _file = ./.;
            nixpkgs.pkgs = liteSystemPkgs;
            networking.hostName = hostName;
          }
        ]
        ++ lib.optionals useHomeManager [
          homeManagerSystemModule
          {
            _file = ./.;
            home-manager = {
              sharedModules = [
                cfg.homeModule
              ];
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
      modules = [
        cfg.homeModule
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
      ];

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
    lite-system = mkOption {
      type = liteSystemType;
      default = {};
      description = ''
        The config for lite-system.
      '';
    };
  };

  config = {
    # Setting the systems to cover all configured hosts
    systems = lib.unique (attrValues (mapAttrs (_: v: v.system) cfg.hosts));

    flake = systemAttrset;

    perSystem = {
      system,
      liteSystemPkgs,
      ...
    }: {
      _file = ./.;
      config = let
        selectedPkgs = import cfg.nixpkgs.nixpkgs {
          inherit system;
          overlays = cfg.nixpkgs.overlays;
          config = cfg.nixpkgs.config;
        };
      in {
        # Make this OptionDefault so that users are able to override this pkg.
        _module.args.liteSystemPkgs = lib.mkOptionDefault selectedPkgs;

        _module.args.pkgs = lib.mkIf cfg.nixpkgs.setPerSystemPkgs liteSystemPkgs;

        packages = let
          overlayPackages = let
            overlayFn = lib.composeManyExtensions liteSystemPkgs.overlays;
            overlayPackageNames =
              # Here we use the final pkgs as both prev and final arg for the overlay function.
              # This should be fine because we only care about attr names.
              attrNames (overlayFn liteSystemPkgs liteSystemPkgs);
            overlayPackageEntries =
              map (name: {
                inherit name;
                value = liteSystemPkgs.${name} or null;
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
            homeConfigurations = createHomeConfigurations liteSystemPkgs;
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
