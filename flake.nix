{
  description = "A flake module to help build NixOS, nix-darwin and Home Manager configurations.";
  outputs = {...}: {
    flakeModule = ./flake-module.nix;
  };
}
