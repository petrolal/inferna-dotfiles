require("default.hypr.startup-cursor")

hl.on("hyprland.start", function()
  -- Applications inherit the user's cursor; only the compositor starts blank.
  local cursor_pending = inferna_startup_cursor_pending or inferna_startup_cursor_pending
  local cursor = inferna_startup_cursor or inferna_startup_cursor
  if cursor_pending and cursor then
    hl.env("XCURSOR_PATH", cursor.path)
    hl.env("XCURSOR_THEME", cursor.xcursor)
  end

  -- Slow app launch fix -- set systemd and D-Bus activation vars before
  -- starting session services.
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")

  hl.exec_cmd("inferna-launch-shell")
  hl.exec_cmd("inferna-provision-first-run")
  hl.exec_cmd("inferna-powerprofiles-init")
  hl.exec_cmd("inferna-hyprland-software-rendering")
  hl.exec_cmd(o.launch("inferna-hyprland-monitor-watch"))
  hl.exec_cmd(o.launch("udiskie --automount --no-notify --no-tray"))

  -- Start the herdr server inside the graphical session so its panes inherit
  -- WAYLAND_DISPLAY. Otherwise the first SSH login from a remote herdr starts
  -- it with a tty environment, and agents in its panes can't read the clipboard.
  hl.exec_cmd(o.launch("herdr server"))

  -- Run post-boot hooks after startup config has loaded.
  hl.exec_cmd("sleep 2 && inferna-hook post-boot")
end)
