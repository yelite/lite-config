toplevel @ {
  inputs,
  lib,
  flake-parts-lib,
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
    mkOption
    mapAttrs
    types
    recursiveUpdateUntil
    isDerivation
    literalExpression
    ;
  inherit
    (flake-parts-lib)
    mkPerSystemOption
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
      exportPackagesInOverlays = mkOption {
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
          Whether the `pkgs` used in lite-system should be set as the `pkgs` arg for
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
        type = types.nullOr types.path;
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

      builder = mkOption {
        type = builderOptionType;
        default = {};
        description = ''
          Options about system configuration builder.

          By default, the builder for MacOS is `inputs.nix-darwin.lib.darwinSystem`
          and the builder for NixOS is {option}`lite-system.nixpkgs.nixpkgs.lib.nixosSystem`.
        '';
      };

      systemModule = mkOption {
        description = ''
          The system module to be imported by all system configurations.
        '';
        type = types.path;
      };

      hostModuleDir = mkOption {
        description = ''
          The directory that contains host modules. Module at
          `''${hostMouduleDir}/''${hostName}` will be imported in
          the configuration for host `hostName` by default.

          The actual host module can be overridden in
          {option}`lite-system.hosts.<hostName>.hostModule`.
        '';
        type = types.path;
      };
    };
  };

  makeSystemConfig = hostName: hostConfig:
    withSystem hostConfig.system ({liteSystemPkgs, ...}: let
      hostPlatform = liteSystemPkgs.stdenv.hostPlatform;
      hostModule =
        if hostConfig.hostModule == null
        then "${cfg.hostModuleDir}/${hostName}"
        else hostConfig.hostModule;
      builderArgs = {
        specialArgs = {
          inherit inputs hostPlatform;
        };
        modules = [
          hostModule
          cfg.systemModule
          {
            nixpkgs.pkgs = liteSystemPkgs;
            networking.hostName = hostName;
          }
        ];
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
in {
  options = {
    lite-system = mkOption {
      type = liteSystemType;
      default = {};
      description = ''
        The config for lite-system.
      '';
    };

    perSystem = mkPerSystemOption ({
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
          overlayPackages = listToAttrs validOverlayPackageEntries;
        in
          lib.mkIf cfg.nixpkgs.exportPackagesInOverlays overlayPackages;
      };
    });
  };

  config = {
    # Setting the systems to cover all configured hosts
    systems = lib.unique (attrValues (mapAttrs (_: v: v.system) cfg.hosts));

    flake = systemAttrset;
  };
}
