{
  description = "A flake module to help build NixOS, nix-darwin or Home Manager configurations.";
  outputs = {...}: {
    flakeModule = ./flake-module.nix;
  };
}
