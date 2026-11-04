-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Swap fullscreen shortcuts; let the scrolling layout preserve window widths.
hl.unbind("SUPER + F")
hl.unbind("SUPER + ALT + F")
o.bind("SUPER + F", "Toggle full-width window", hl.dsp.window.fullscreen({ mode = "maximized", layout_aware = true }))
o.bind("SUPER + ALT + F", "Toggle fullscreen", hl.dsp.window.fullscreen({ mode = "fullscreen", layout_aware = true }))
o.bind("SUPER + CTRL + ALT + F", "Toggle all windows full width", os.getenv("HOME") .. "/.local/bin/hypr-all-full-width")

-- Native window swaps exchange column widths and can break maximized restore
-- sizes. Move the entire scrolling column, including its remembered width.
-- These replace Omarchy's "Swap window to the left/right" bindings.
for _, item in ipairs({ { "LEFT", "l" }, { "RIGHT", "r" } }) do
  local direction = item[2]
  hl.unbind("SUPER + SHIFT + " .. item[1])
  o.bind("SUPER + SHIFT + " .. item[1], "Move column " .. item[1]:lower(), function()
    local active = hl.get_active_window()
    if active and not active.floating and active.workspace
        and active.workspace.tiled_layout == "scrolling" then
      hl.dispatch(hl.dsp.layout("swapcol " .. direction))
    else
      hl.dispatch(hl.dsp.window.swap({ direction = direction }))
    end
  end)
end

-- Navigate scrolling columns without shrinking the window being left.
-- Scrolling workspaces use the same in-process carousel as the 3-finger swipe
-- (no helper process, wraps at the ends); other layouts keep the smart-focus helper.
local carousel = require("hypr.carousel")
for _, item in ipairs({
  { "LEFT", "l" }, { "RIGHT", "r" },
}) do
  local direction = item[2]
  hl.unbind("SUPER + " .. item[1])
  o.bind("SUPER + " .. item[1], "Focus window " .. item[1]:lower(), function()
    local active = hl.get_active_window()
    if active and not active.floating and active.workspace
        and active.workspace.tiled_layout == "scrolling" then
      carousel.step(direction)
    else
      hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/hypr-smart-focus " .. direction)
    end
  end)
end

-- Vertical navigation switches workspaces; horizontal navigation stays in the strip.
hl.unbind("SUPER + UP")
hl.unbind("SUPER + DOWN")
o.bind("SUPER + UP", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
o.bind("SUPER + DOWN", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))

-- Screenshot shortcuts; keep the default Super+Shift+3/4 workspace moves.
-- Snip replaces the screenshot shelf. Skipped when Snip is not installed.
local snip_file = io.open("/usr/share/snip/hypr/snip.lua")
if snip_file then
snip_file:close()
snip_keys = false
dofile("/usr/share/snip/hypr/snip.lua")
hl.unbind("SUPER + CTRL + code:12")
hl.unbind("SUPER + CTRL + code:13")
hl.unbind("SUPER + CTRL + SHIFT + S")
o.bind("SUPER + CTRL + code:12", "Snip: Capture fullscreen", hl.dsp.global("snip:fullscreen"))
o.bind("SUPER + CTRL + code:13", "Snip: Capture area", hl.dsp.global("snip:area"))
o.bind("SUPER + CTRL + SHIFT + S", "Snip: Open capture history", hl.dsp.global("snip:history"))
-- Replaces Omarchy screen recording; press again to stop in Snip.
hl.unbind("ALT + PRINT")
o.bind("ALT + PRINT", "Snip: Record screen", hl.dsp.global("snip:record"))
end

-- flea --default: begin. Written by `flea --default`; `flea --default off` removes the block whole.
-- Only when flea is installed; otherwise Omarchy's file manager keys stay.
if os.execute("command -v flea >/dev/null 2>&1") then
hl.unbind("SUPER + SHIFT + F")
o.bind("SUPER + SHIFT + F", "File manager", { launch = 'flea --gui' })
hl.unbind("SUPER + ALT + SHIFT + F")
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)", { launch = 'flea --gui "$(omarchy-cmd-terminal-cwd)"' })
end
-- flea --default: end.

-- flea --picker: begin. Written by `flea --picker`; `flea --picker off` removes the block whole.
o.window("com.thisisgm.flea.picker", { tag = "+floating-window" })
-- flea --picker: end.

-- ML4W style keybinding aliases
o.bind("SUPER + B", "Open Browser", { omarchy = "browser" })
o.bind("SUPER + E", "Open File Manager", hl.dsp.exec_cmd("thunar"))
o.bind("SUPER + CTRL + RETURN", "Open application launcher", { menu = "root" })
o.bind("SUPER + SHIFT + Q", "Force quit active window", hl.dsp.exec_cmd("hyprctl activewindow | grep pid | tr -d 'pid:' | xargs kill"))
o.bind("SUPER + CTRL + K", "Keybindings cheat sheet", "omarchy-menu-keybindings")
o.bind("SUPER + CTRL + P", "Power Menu", { menu = "system" })

-- Rebind SUPER + SLASH from monitor scaling to cheat sheet (avoid accidental zoom)
hl.unbind("SUPER + SLASH")
o.bind("SUPER + SLASH", "Keybindings cheat sheet", "omarchy-menu-keybindings")

-- Dedicated monitor zoom controls
o.bind("SUPER + equal", "Zoom in (Scale up)", "omarchy-hyprland-monitor-scaling up")
o.bind("SUPER + minus", "Zoom out (Scale down)", "omarchy-hyprland-monitor-scaling down")


