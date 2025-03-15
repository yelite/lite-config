{
  inputs,
  lib,
  withSystem,
  config,
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
  cfg = config.lite-config;

  overlayType = types.uniq (types.functionTo (types.functionTo (types.lazyAttrsOf types.unspecified)));
  nixpkgsOptionType = types.submodule {
    options = {
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
        type = types.listOf overlayType;
        description = ''
          List of overlays to use with the Nix Packages collection.
        '';
        example =
          literalExpression
          ''
            [
              inputs.neovim-nightly-overlay.overlays.default
            ]
          '';
      };
      setPerSystemPkgs = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether the nixpkgs used in lite-config should also be set as the `pkgs` arg for
          the perSystem flake-parts module.
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
        example = ''
          "x86_64-linux"
        '';
      };
      modules = mkOption {
        type = types.listOf types.deferredModule;
        default = [];
        description = ''
          Modules to be imported by this host.
        '';
      };
    };
  };
  homeManagerConfigType = types.submodule {
    options = {
      modules = mkOption {
        type = types.listOf types.deferredModule;
        default = [];
        description = ''
          Modules to be imported by the home manager.
        '';
      };
    };
  };
  flakeOptionType = types.submodule {
    options = {
      nixpkgs = mkOption {
        type = types.path;
        default = inputs.nixpkgs;
        defaultText = literalExpression ''
          inputs.nixpkgs
        '';
        description = ''
          The nixpkgs flake. This option should be set if the `nixpkgs` flake
            is under a different name in flake inputs.
        '';
      };
      nix-darwin = mkOption {
        type = types.path;
        default = inputs.nix-darwin;
        defaultText = literalExpression ''
          inputs.nix-darwin
        '';
        description = ''
          The nix-darwin flake. This option should be set if the `nix-darwin` flake
          is under a different name in flake inputs.
        '';
      };
      home-manager = mkOption {
        type = types.path;
        default = inputs.home-manager;
        defaultText = literalExpression ''
          inputs.home-manager
        '';
        description = ''
          The home-manager flake. This option should be set if the `home-manager` flake
          is under a different name in flake inputs.
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

      flakes = mkOption {
        type = flakeOptionType;
        default = {};
        description = ''
          Options for the flakes used by lite-config.
        '';
      };

      hostModules = mkOption {
        type = types.listOf types.deferredModule;
        default = [];
        description = ''
          Shared system modules (NixOS or nix-darwin) to be imported by all hosts.
        '';
      };

      nixosModules = mkOption {
        type = types.listOf types.deferredModule;
        default = [];
        description = ''
          Shared NixOS modules to be imported by all hosts.
        '';
      };

      darwinModules = mkOption {
        type = types.listOf types.deferredModule;
        default = [];
        description = ''
          Shared nix-darwin modules to be imported by all hosts.
        '';
      };

      hosts = mkOption {
        type = types.attrsOf hostConfigType;
        default = {};
        description = ''
          Host configurations.
        '';
      };

      homeModules = mkOption {
        type = types.listOf types.deferredModule;
        default = [];
        description = ''
          Home manager modules to be imported by all hosts.
        '';
      };

      homeConfigurations = mkOption {
        type = types.attrsOf homeManagerConfigType;
        default = {};
        description = ''
          Per-user Home Manager module used for exporting homeConfigurations to be used
          by systems other than NixOS and nix-darwin.

          The exported homeConfigurations will import `lite-config.homeModules` and the modules
          specified in the `modules` attribute.
        '';
        example =
          literalExpression
          ''
            {
              joe = {
                modules = [./home/joe];
              };
            }
          '';
      };
    };
  };

  makeSystemConfig = hostName: hostConfig:
    withSystem hostConfig.system ({liteConfigPkgs, ...}: let
      hostPlatform = liteConfigPkgs.stdenv.hostPlatform;
      homeManagerSystemModule =
        if hostPlatform.isLinux
        then cfg.flakes.home-manager.nixosModules.default
        else if hostPlatform.isDarwin
        then cfg.flakes.home-manager.darwinModules.default
        else throw "System type ${hostPlatform.system} not supported.";
      platformModules =
        if hostPlatform.isLinux
        then cfg.nixosModules
        else if hostPlatform.isDarwin
        then cfg.darwinModules
        else throw "System type ${hostPlatform.system} not supported.";
      specialArgs = {
        inherit inputs hostPlatform;
      };
      modules =
        hostConfig.modules
        ++ cfg.hostModules
        ++ [
          {
            _file = ./.;
            nixpkgs.pkgs = liteConfigPkgs;
            networking.hostName = hostName;
          }
        ]
        ++ platformModules
        ++ [
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
      then {nixosConfigurations.${hostName} = cfg.flakes.nixpkgs.lib.nixosSystem builderArgs;}
      else if hostPlatform.isDarwin
      then {darwinConfigurations.${hostName} = cfg.flakes.nix-darwin.lib.darwinSystem builderArgs;}
      else throw "System type ${hostPlatform.system} not supported.");

  mkHomeConfiguration = pkgs: configName: homeConfig:
    cfg.flakes.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules =
        homeConfig.modules
        ++ cfg.homeModules
        ++ [
          ({config, ...}: let
            inherit (pkgs.stdenv) hostPlatform;
            defaultHome =
              if hostPlatform.isLinux
              then "/home/${config.home.username}"
              else if hostPlatform.isDarwin
              then "/Users/${config.home.username}"
              else throw "System type ${hostPlatform.system} not supported.";
            # if username has an @, use the part before the @
            matches = lib.strings.match "([^@]*)@.*" configName;
            username =
              if matches == null
              then configName
              else builtins.head matches;
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

    flake = let
      hostConfigAttrsets = attrValues (mapAttrs makeSystemConfig cfg.hosts);
      # Merge the first two levels of the system configuration
      mergeSysConfig = a: b: recursiveUpdateUntil (path: _: _: (length path) > 2) a b;
    in
      foldl' mergeSysConfig {} hostConfigAttrsets;

    perSystem = {
      system,
      liteConfigPkgs,
      ...
    }: {
      _file = ./.;
      config = let
        pkgs = import cfg.flakes.nixpkgs {
          inherit system;
          overlays = cfg.nixpkgs.overlays;
          config = cfg.nixpkgs.config;
        };
      in {
        _module.args.liteConfigPkgs = pkgs;
        _module.args.pkgs = lib.mkIf cfg.nixpkgs.setPerSystemPkgs liteConfigPkgs;
        packages.homeConfigurations = createHomeConfigurations liteConfigPkgs;
      };
    };
  };
}
