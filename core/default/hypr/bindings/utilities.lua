o.bind("SUPER + SPACE", "Inferna menu", { menu = "root" })
o.bind("SUPER + ALT + SPACE", "Apps", "inferna-shell inferna.dock apps")
o.bind("SUPER + CTRL + E", "Emojis", { panel = "inferna.emojis" })
o.bind("SUPER + CTRL + C", "Capture menu", { menu = "capture" })
o.bind("SUPER + CTRL + O", "Toggle menu", { menu = "toggle" })
o.bind("SUPER + CTRL + H", "Hardware menu", { menu = "hardware" })
o.bind("SUPER + SHIFT + code:201", "Inferna menu", { menu = "root" })
o.bind("SUPER + ESCAPE", "System menu", { menu = "system" })
o.bind("XF86PowerOff", "Power menu", { menu = "system" }, { locked = true })
o.bind("SUPER + K", "Keybindings", "inferna-menu-keybindings")
o.bind("SUPER + ALT + K", "Tmux keybindings", "inferna-menu-tmux-keybindings")
o.bind("SUPER + CTRL + K", "Herdr keybindings", "inferna-menu-herdr-keybindings")
o.bind_toggle("SUPER + SHIFT + SPACE", "Toggle top bar", "bar")
o.bind("SUPER + CTRL + SPACE", "Background switcher", { menu = "background" })
o.bind("SUPER + CTRL + W", "Background switcher", { menu = "background" })
o.bind("SUPER + SHIFT + CTRL + SPACE", "Theme menu", { menu = "theme" })
o.bind("SUPER + CTRL + T", "Theme menu", { menu = "theme" })
o.bind("SUPER + BACKSPACE", "Toggle transparency on a window", "inferna-hyprland-window-transparency-toggle")
o.bind("SUPER + SHIFT + BACKSPACE", "Toggle window gaps", "inferna-hyprland-window-gaps-toggle")
o.bind("SUPER + CTRL + BACKSPACE", "Toggle single-window square aspect", "inferna-hyprland-window-single-square-aspect-toggle")
o.bind_toggle("SUPER + CTRL + ALT + F", "Toggle full screen desktop", "fullscreen-desktop")

-- xkbcommon names the comma keysym "comma"; the upper-case "COMMA" does not match.
o.bind("SUPER + comma", "Dismiss, invoke, or focus last notification", { ipc = "notifications.act" })
o.bind("SUPER + SHIFT + comma", "Dismiss all notifications", { ipc = "notifications.dismissAll" })
o.bind("SUPER + CTRL + comma", "Control notifications with the keyboard", { ipc = "notifications.keyboard" })
o.bind("SUPER + ALT + comma", "Dismiss last notification", { ipc = "notifications.dismissOne" })
o.bind("SUPER + SHIFT + ALT + comma", "Open notification history", { ipc = "notifications.showHistory" })
o.bind_toggle("SUPER + CTRL + ALT + comma", "Toggle silencing notifications", "notification-silencing")

o.bind_toggle("SUPER + CTRL + I", "Toggle locking on idle", "idle")
o.bind("SUPER + CTRL + Delete", "Toggle laptop display", "inferna-hyprland-monitor-internal toggle")
o.bind("SUPER + CTRL + ALT + Delete", "Toggle laptop display mirroring", "inferna-hyprland-monitor-internal-mirror toggle")
o.bind("switch:on:Lid Switch", nil, "inferna-system-lid-close", { locked = true })
o.bind("switch:off:Lid Switch", nil, "inferna-hyprland-monitor-clamshell", { locked = true })
-- Apple Silicon reports its lid through the SMC, under its own switch name.
o.bind("switch:on:Apple SMC power/lid events", nil, "inferna-system-lid-close", { locked = true })
o.bind("switch:off:Apple SMC power/lid events", nil, "inferna-hyprland-monitor-clamshell", { locked = true })

o.bind("PRINT", "Screenshot", "inferna-capture-screenshot")
o.bind("SUPER + CTRL + ALT + C", "Screenshot", "inferna-capture-screenshot")
o.bind("ALT + PRINT", "Screenrecording", "inferna-capture-screenrecording --stop-recording || inferna-menu toggle trigger.capture.screenrecord")
o.bind("SUPER + ALT + code:34", "Make webcam overlay smaller", "inferna-capture-webcam-resize smaller")
o.bind("SUPER + ALT + code:35", "Make webcam overlay larger", "inferna-capture-webcam-resize larger")
o.bind("SUPER + PRINT", "Color picker", "pkill hyprpicker || hyprpicker -a")
o.bind("SUPER + CTRL + PRINT", "Extract text (OCR) from screenshot", "inferna-capture-text")

-- Keyboard control for the slurp region picker (see inferna-capture-region).
-- The binds are enabled exactly as long as a selection layer is on screen
-- (slurp opens one per monitor), so they cannot leak or get stuck.
-- They are disabled rather than unbound, since Hyprland's unbind() removes every
-- bind on the chord, the user's own included. Without descriptions, the
-- keybindings menu leaves them out.
local selection_layers = 0
local selection_keys = {
  ["RETURN"] = "--take-window",
  ["CTRL + RETURN"] = "--take-fullscreen",
  ["TAB"] = "--select-window next",
  ["CTRL + TAB"] = "--select-window prev",
  ["LEFT"] = "--select-window left",
  ["RIGHT"] = "--select-window right",
  ["UP"] = "--select-window up",
  ["DOWN"] = "--select-window down",
}
local selection_binds = {}

-- Any unbind of the chord expires the handle, and Hyprland 0.56 dereferences an
-- expired handle in every method but tostring().
local function selection_bind_alive(keybind)
  return keybind ~= nil and tostring(keybind) ~= "HL.Keybind(expired)"
end

hl.on("layer.opened", function(layer)
  if layer.namespace == "selection" then
    selection_layers = selection_layers + 1
    if selection_layers == 1 then
      for keys, mode in pairs(selection_keys) do
        if not selection_bind_alive(selection_binds[keys]) then
          selection_binds[keys] = hl.bind(keys, hl.dsp.exec_cmd("inferna-capture-region " .. mode))
        end
        selection_binds[keys]:set_enabled(true)
      end
    end
  end
end)

hl.on("layer.closed", function(layer)
  if layer.namespace == "selection" and selection_layers > 0 then
    selection_layers = selection_layers - 1
    if selection_layers == 0 then
      for _, keybind in pairs(selection_binds) do
        if selection_bind_alive(keybind) then
          keybind:set_enabled(false)
        end
      end
    end
  end
end)

o.bind("SUPER + CTRL + S", "Share", { menu = "share" })

o.bind("SUPER + CTRL + PERIOD", "Transcode", "inferna-transcode")

o.bind("SUPER + CTRL + R", "Set reminder", { menu = "reminder-set" })
o.bind("SUPER + CTRL + ALT + R", "Show reminders", "inferna-reminder show")
o.bind("SUPER + SHIFT + CTRL + R", "Clear reminders", "inferna-reminder clear")

o.bind("SUPER + CTRL + ALT + T", "Show time", "inferna-notification-time")
o.bind("SUPER + CTRL + ALT + B", "Show battery remaining", "inferna-notification-battery")
o.bind("SUPER + CTRL + ALT + W", "Toggle weather", "inferna-notification-weather")

o.bind("SUPER + SHIFT + CTRL + A", "Agent", "inferna-agent --pick")
o.bind("SUPER + CTRL + A", "Audio", { panel = "inferna.audio" })
o.bind("SUPER + CTRL + B", "Bluetooth", { panel = "inferna.bluetooth" })
o.bind("SUPER + CTRL + D", "Display", { panel = "inferna.monitor" })
o.bind("SUPER + CTRL + ALT + D", "Calendar", { panel = "inferna.clock" })
o.bind("SUPER + CTRL + ALT + E", "World clock", { panel = "inferna.elsewhen" })
o.bind("SUPER + CTRL + N", "Network", { panel = "inferna.network" })
o.bind("SUPER + CTRL + P", "Power", { panel = "inferna.power" })
o.bind("SUPER + SHIFT + T", "Activity", { tui = "btop" })

-- The letters above name a panel; the numbers count them. 1 is the leftmost
-- panel in the bar's right section, and a widget with no panel of its own (the
-- tray) is not counted, so the number matches the icon a user would point at.
-- A bar with fewer panels than this leaves the tail of the range doing nothing.
for panel = 1, 9 do
  o.bind(
    "SUPER + CTRL + code:" .. tostring(panel + 9),
    "Bar panel " .. panel,
    "inferna-shell -q shell togglePanelAt right " .. panel
  )
end

o.bind("SUPER + CTRL + Z", "Zoom in", function()
  local zoom = hl.get_config("cursor.zoom_factor") or 1
  hl.config({ cursor = { zoom_factor = zoom + 1 } })
end)

o.bind("SUPER + CTRL + ALT + Z", "Reset zoom", function()
  hl.config({ cursor = { zoom_factor = 1 } })
end)

o.bind("SUPER + CTRL + L", "Lock system", "inferna-system-lock")
