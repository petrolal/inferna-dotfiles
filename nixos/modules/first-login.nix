{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.dotfiles.firstLogin;

  firstLoginScript = pkgs.writeShellApplication {
    name = "inferna-first-login";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      dconf
      gawk
      glib
      gnome-shell
      gnused
      libnotify
    ];
    text = ''
      set -euo pipefail

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/inferna"
      marker="$state_dir/initialized"
      mkdir -p "$state_dir"

      if [[ -f "$marker" ]]; then
        exit 0
      fi

      repo="''${INFERNA_DOTFILES:-${config.dotfiles.repoPath}}"
      if [[ ! -x "$repo/install.sh" ]]; then
        echo "inferna-first-login: $repo/install.sh not found; skipping." >&2
        exit 0
      fi

      # Wait briefly for the GNOME user D-Bus session to be ready.
      for _ in $(seq 1 15); do
        if [[ -n "''${DBUS_SESSION_BUS_ADDRESS:-}" ]] && dconf read / >/dev/null 2>&1 || [[ -S "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]]; then
          if [[ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" && -S "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
          fi
          break
        fi
        sleep 1
      done

      "$repo/install.sh" --yes

      if [[ -n "''${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        date -Is > "$marker"
        notify-send -a "Inferna" "Inferna Rice ready" "GNOME theme, extensions, and dotfiles applied." 2>/dev/null || true
      fi
    '';
  };
in
{
  options.dotfiles.firstLogin.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Automatically apply Inferna user dotfiles, GNOME theme, and dconf extensions on first graphical login.";
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.inferna-first-login = {
      description = "Inferna Dotfiles First-Login GNOME Setup";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      unitConfig = {
        ConditionPathExists = "!%h/.local/state/inferna/initialized";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${firstLoginScript}/bin/inferna-first-login";
      };
    };
  };
}
