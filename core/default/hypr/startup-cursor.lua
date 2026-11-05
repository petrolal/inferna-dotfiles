local function cursor_theme(value)
  if value and value ~= "" and value ~= "inferna-startup" and value ~= "inferna-startup" then return value end
end

local function normal_theme(interrupted)
  local current = os.getenv("XCURSOR_THEME")
  local theme = cursor_theme(current)
  -- Only a lost preference needs recovering; an unset theme still means the default alias.
  if theme or not (interrupted or current == "inferna-startup" or current == "inferna-startup") then return theme or "default" end
  theme = cursor_theme(os.getenv("INFERNA_STARTUP_CURSOR_THEME") or os.getenv("INFERNA_STARTUP_CURSOR_THEME"))
  if theme then return theme end
  local pipe = io.popen("gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null", "r")
  if pipe then
    theme = cursor_theme((pipe:read("*a") or ""):match("^'(.-)'%s*$"))
    pipe:close()
  end
  return theme or "default"
end

local function normal_path()
  local kept = {}
  for entry in (os.getenv("XCURSOR_PATH") or "~/.local/share/icons:~/.icons:/usr/share/icons:/usr/share/pixmaps"):gmatch("[^:]+") do
    if not entry:match("/default/hypr/cursors$") then table.insert(kept, entry) end
  end
  return table.concat(kept, ":")
end

-- Hyprland polls cursor.invisible, so its first frames need a blank cursor too.
function inferna_startup_cursor_restore(loaded)
  if not inferna_startup_cursor_pending then return end
  local cursor = inferna_startup_cursor
  if loaded then
    inferna_startup_cursor_pending = false
    hl.env("INFERNA_STARTUP_CURSOR_SESSION", "")
    hl.env("INFERNA_STARTUP_CURSOR_THEME", "")
    hl.env("INFERNA_STARTUP_CURSOR_SESSION", "")
    hl.env("INFERNA_STARTUP_CURSOR_THEME", "")
    hl.config({ cursor = cursor.config })
    if cursor.config.enable_hyprcursor and cursor.hyprcursor then
      hl.exec_cmd("hyprctl setcursor " .. o.shell_quote(cursor.hyprcursor) .. " " .. cursor.size)
    end
    hl.exec_cmd("xsetroot -cursor_name left_ptr >/dev/null 2>&1 || true")
  elseif not cursor.restoring then
    -- Reload the normal Xcursor fallback before enabling Hyprcursor or GSettings.
    cursor.restoring = true
    hl.env("XCURSOR_PATH", cursor.path)
    hl.env("XCURSOR_THEME", cursor.xcursor)
    hl.exec_cmd("dbus-update-activation-environment --systemd XCURSOR_PATH XCURSOR_THEME")
    local complete = "if inferna_startup_cursor and inferna_startup_cursor.xcursor == " .. string.format("%q", cursor.xcursor)
      .. " and inferna_startup_cursor.size == " .. cursor.size .. " then inferna_startup_cursor_restore(true) end"
    hl.exec_cmd("hyprctl setcursor " .. o.shell_quote(cursor.xcursor) .. " " .. cursor.size
      .. " && hyprctl eval " .. o.shell_quote(complete))
  end
end
inferna_startup_cursor_restore = inferna_startup_cursor_restore

hl.on("config.reloaded", function()
  local recover = false
  if inferna_startup_cursor_pending == nil then
    -- An ordinary reload must not hide the pointer, but an interrupted reveal survives.
    local cold = #hl.get_monitors() == 0
    local session = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
    local interrupted = session and (os.getenv("INFERNA_STARTUP_CURSOR_SESSION") == session or os.getenv("INFERNA_STARTUP_CURSOR_SESSION") == session)
    recover = not cold and not interrupted and (os.getenv("XCURSOR_THEME") == "inferna-startup" or os.getenv("XCURSOR_THEME") == "inferna-startup")
    inferna_startup_cursor_pending = cold or interrupted or recover
    if inferna_startup_cursor_pending then
      local hyprcursor = hl.get_config("cursor.enable_hyprcursor")
      inferna_startup_cursor = {
        config = {
          invisible = hl.get_config("cursor.invisible"),
          enable_hyprcursor = hyprcursor,
          sync_gsettings_theme = hl.get_config("cursor.sync_gsettings_theme"),
        },
        hyprcursor = os.getenv("HYPRCURSOR_THEME"),
        size = tonumber((hyprcursor and os.getenv("HYPRCURSOR_SIZE")) or os.getenv("XCURSOR_SIZE")) or 24,
        path = normal_path(),
        xcursor = normal_theme(interrupted),
      }
      if inferna_startup_cursor.size <= 0 then inferna_startup_cursor.size = 24 end
      -- Compositor environment survives Lua reloads; a session id prevents stale inheritance.
      hl.env("INFERNA_STARTUP_CURSOR_THEME", inferna_startup_cursor.xcursor)
      hl.env("INFERNA_STARTUP_CURSOR_SESSION", os.getenv("HYPRLAND_INSTANCE_SIGNATURE"))
      hl.env("INFERNA_STARTUP_CURSOR_THEME", inferna_startup_cursor.xcursor)
      hl.env("INFERNA_STARTUP_CURSOR_SESSION", os.getenv("HYPRLAND_INSTANCE_SIGNATURE"))
      local core_path = os.getenv("INFERNA_PATH") or os.getenv("INFERNA_PATH")
      if cold and core_path then
        hl.env("XCURSOR_PATH", core_path .. "/default/hypr/cursors:" .. inferna_startup_cursor.path)
        hl.env("XCURSOR_THEME", "inferna-startup")
      else
        hl.env("XCURSOR_PATH", inferna_startup_cursor.path)
        hl.env("XCURSOR_THEME", inferna_startup_cursor.xcursor)
      end
    end
  end
  if inferna_startup_cursor_pending then
    -- Keep the temporary cursor private to the compositor, including GSettings.
    hl.config({ cursor = { invisible = true, enable_hyprcursor = false, sync_gsettings_theme = false } })
    hl.timer(function()
      if inferna_startup_cursor_pending then
        inferna_startup_cursor.restoring = false
        inferna_startup_cursor_restore()
      end
    end, { timeout = 15000, type = "oneshot" })
    if recover then inferna_startup_cursor_restore() end
  end
end)
