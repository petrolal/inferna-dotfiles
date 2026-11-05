-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Inferna / Pebble Shell bootstrap path setup
local dotfiles = os.getenv("INFERNA_DOTFILES") or (os.getenv("HOME") .. "/inferna-dotfiles")
local inferna_core = os.getenv("INFERNA_PATH") or os.getenv("OMARCHY_PATH") or (dotfiles .. "/core")
hl.env("INFERNA_PATH", inferna_core)
hl.env("OMARCHY_PATH", inferna_core)
dofile(inferna_core .. "/default/hypr/bootstrap.lua")

-- Disable all Inferna default bindings. Add your own in hypr/bindings.lua.
-- inferna_default_bindings = false
--
-- Or disable only bindings for Inferna's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- inferna_preinstalled_bindings = false

-- Load Inferna defaults.
require("default.hypr.inferna")

-- Put your personal overrides in these files. They're loaded after Inferna's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
local function safe_require(mod)
  local ok, err = pcall(require, mod)
  if not ok and not string.find(err, "not found") then
    print("[hyprland.lua] Error loading " .. mod .. ": " .. tostring(err))
  end
end

safe_require("hypr.monitors")
safe_require("hypr.input")
safe_require("hypr.bindings")
safe_require("hypr.looknfeel")
safe_require("hypr.autostart")


-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Glass surfaces: summoned shell popups (polkit, clipboard, emojis) use the
-- bar's sans instead of monospace. Takes effect on the next shell start.
hl.env("INFERNA_MENU_FONT", "Adwaita Sans")
hl.env("OMARCHY_MENU_FONT", "Adwaita Sans")

do local p = os.getenv("HOME") .. "/.config/hypr/theme_studio_border.lua"; local f = io.open(p); if f then f:close(); dofile(p) end end  -- Theme Studio: window border colors (written by its panel)
do local p = os.getenv("HOME") .. "/.config/hypr/recessed_windows.lua"; local f = io.open(p); if f then f:close(); dofile(p) end end  -- Depth: recessed/raised windows (written by its panel)

do local d = debug.getinfo(1, "S").source:match("^@(.*/)") or os.getenv("HOME") .. "/.config/hypr/"; local p = d .. "tricky-tiles.lua"; local f = io.open(p); if f then f:close(); dofile(p) end end -- Tricky Tiles (remove via its panel)
do local d = debug.getinfo(1, "S").source:match("^@(.*/)") or os.getenv("HOME") .. "/.config/hypr/"; local p = d .. "softly.lua"; local f = io.open(p); if f then f:close(); dofile(p) end end -- Softly (remove via its panel)
