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
        defaultText = literalExpression ''
          inputs.nixpkgs
        '';
        description = ''
          The nixpkgs flake to use. By default, it uses the flake input 'nixpkgs'.
          You only need to specify this if you want to use a different nixpkgs or
          nixpkgs is under a different name in your flake inputs.
        '';
      };
      config = mkOption {
        default = {};
        type = types.attrs;
        description = ''
          The configuration to apply to nixpkgs.
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
          List of overlays to apply to nixpkgs.
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
          Whether packages in the overlays should be exported as packages of the flake.
        '';
      };
      setPerSystemPkgs = mkOption {
        default = true;
        type = types.bool;
        description = ''
          Whether the nixpkgs used in lite-system should be set as the `pkgs` arg for
          perSystem modules.
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
          when the `nix-darwin` flake is under a different name as flake input.
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
          Config for nixpkgs used by lite-system.
        '';
      };

      hosts = mkOption {
        type = types.attrsOf hostConfigType;
        default = {};
        description = ''
          Host configurations
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

          The actual host module can be overridden in
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
          You only need to set this if home manager isn't named as `home-manager` in your flake inputs.
          This has no effect if {option}`lite-system.homeModule` is null.
        '';
      };

      homeConfigurations = mkOption {
        type = types.attrsOf types.deferredModule;
        default = {};
        description = ''
          Per-user Home Manager module used for exporting homeConfigurations for systems other than NixOS and nix-darwin.
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
        else throw "Not supported system type ${hostPlatform.system}";
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
      else throw "Not supported system type ${hostPlatform.system}");
  systemAttrset = let
    # Merge the first two levels
    mergeSysConfig = a: b: recursiveUpdateUntil (path: _: _: (length path) > 2) a b;
    sysConfigAttrsets = attrValues (mapAttrs makeSystemConfig cfg.hosts);
  in
    foldl' mergeSysConfig {} sysConfigAttrsets;

  overlayPackageNames = let
    overlay = lib.composeManyExtensions cfg.nixpkgs.overlays;
  in
    attrNames (overlay null null);

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
            else throw "Not supported system type ${hostPlatform.system}";
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
        echo "This derivation is a dummy package to ground homeConfigurations under the flake outputs."
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
        _module.args.pkgs = lib.mkIf cfg.nixpkgs.setPerSystemPkgs selectedPkgs;
        # Make this OptionDefault so that users are able to override this pkg.
        _module.args.liteSystemPkgs = lib.mkOptionDefault selectedPkgs;

        packages = let
          overlayPackages = let
            selectPkg = name: {
              inherit name;
              value = liteSystemPkgs.${name} or null;
            };
            # Some overlay provides non-derivation at the top level, which
            # breaks `nix flake show`. Those packages are usually not interesting
            # from system configuration's perspective. Therefore they are filtered
            # out.
            isValidPackageEntry = e: isDerivation e.value;
            overlayPackageEntries = map selectPkg overlayPackageNames;
            validOverlayPackageEntries = filter isValidPackageEntry overlayPackageEntries;
          in
            listToAttrs validOverlayPackageEntries;

          homeManagerPackages = {
            home-manager = cfg.homeManagerFlake.packages.${system}.default;
            homeConfigurations = createHomeConfigurations liteSystemPkgs;
          };
        in
          mkMerge [(mkIf cfg.nixpkgs.exportOverlayPackages overlayPackages) (mkIf useHomeManager homeManagerPackages)];
      };
    };
  };
}
