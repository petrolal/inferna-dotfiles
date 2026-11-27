{
  config,
  pkgs,
  lib,
  ...
}:

let
  username = config.dotfiles.username;
  userDesc = config.dotfiles.userDescription;
in
{
  options.dotfiles = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "petrolal";
      description = "Primary user account name.";
    };
    userDescription = lib.mkOption {
      type = lib.types.str;
      default = "Petrola Lucas";
      description = "Full user description.";
    };
    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/${username}/inferna-dotfiles";
      description = "Absolute path to this dotfiles checkout (INFERNA_DOTFILES).";
    };
    wheelNeedsPassword = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether members of the wheel group must enter a password for sudo.";
    };
  };

  config = {
    users.users.${username} = {
      isNormalUser = true;
      description = userDesc;
      extraGroups = [
        "networkmanager"
        "wheel"
      ] ++ lib.optional config.dotfiles.containers.enable "docker";
      shell = pkgs.fish;
    };

    # Default login/interactive shell. Enabling the module registers fish in
    # environment.shells and wires direnv's fish hook automatically (see
    # programs.direnv in development.nix). Per-user config lives in
    # fish/ (deployed to ~/.config/fish/ by ./install.sh).
    programs.fish.enable = true;

    security.sudo.wheelNeedsPassword = config.dotfiles.wheelNeedsPassword;

    # Keep Firefox available as a fallback browser when dailyApps (Google Chrome) is disabled.
    programs.firefox.enable = lib.mkDefault (!config.dotfiles.packages.dailyApps.enable);
  };
}
