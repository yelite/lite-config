{
  description = "A simple and opinionated way to define system configurations with `flake-parts`.";
  outputs = {...}: {
    flakeModule = ./flake-module.nix;
  };
}
