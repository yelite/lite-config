{
  description = "A flake module to help build NixOS, nix-darwin and Home Manager configurations.";
  outputs = {self, ...}: {
    flakeModules.default = ./flake-module.nix;
    flakeModule = self.flakeModules.default;
  };
}
