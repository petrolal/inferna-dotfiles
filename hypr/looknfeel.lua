-- Change the default Inferna look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--   },
-- })

-- Niri-like side-scrolling (carousel) layout.
hl.config({
  scrolling = {
    -- Hover changes keyboard focus without pulling a neighboring column into view.
    -- Keep explicit focus/navigation working; suppress hover-driven scrolling.
    follow_min_visible = 1.0,
  },
  general = {
    layout = "scrolling",
    gaps_in = 8,
    gaps_out = 16,
    border_size = 1,
  },
  -- The Inferna shell also uses this radius for its panels and controls.
  decoration = {
    rounding = 14,
    rounding_power = 2.0,
    blur = {
      enabled = true,
      size = 6,
      passes = 2,
      xray = false,
      noise = 0.055,
      contrast = 1.0,
      brightness = 1.0,
    },
    shadow = {
      enabled = true,
      range = 20,
      render_power = 3,
      color = "rgba(00000033)",
    },
  },
  group = {
    groupbar = {
      gradient_rounding = 10,
    },
  },
})

-- macOS-style motion, 2026-10-24: shorter durations, responsive start, soft landing.
-- Speeds are in tenths of a second (2.8 = 280 ms). Inferna defaults were
-- windows 3.79, windowsIn 4.1 popin 87%, windowsOut 1.49 linear, border 5.39.
-- macEase (easeOutQuart) is slightly less front-loaded than easeOutQuint, which
-- spreads movement more evenly across frames on this 60 Hz panel.
hl.curve("macEase", { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })
hl.curve("macExit", { type = "bezier", points = { { 0.3, 0 }, { 0.8, 0.15 } } })
local move = 2.8 -- window moves, carousel steps, workspace slides (kept matched)

hl.animation({ leaf = "windows", enabled = true, speed = move, bezier = "macEase" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.2, bezier = "macEase", style = "popin 92%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.4, bezier = "macExit", style = "popin 95%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.8, bezier = "macEase" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.3, bezier = "macExit" })
hl.animation({ leaf = "fade", enabled = true, speed = 2.0, bezier = "macEase" })
hl.animation({ leaf = "border", enabled = true, speed = 2.5, bezier = "macEase" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 2.0, bezier = "macEase", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.3, bezier = "macExit", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.6, bezier = "macEase" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.1, bezier = "macExit" })
-- Workspaces stay vertical and match window movement, as before.
hl.animation({ leaf = "workspaces", enabled = true, speed = move, bezier = "macEase", style = "slidevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = move, bezier = "macEase", style = "slidevert" })

-- Frost only the painted pill, leaving its transparent rounded corners clear.
-- Normal backdrop blur preserves separate colors beneath its left/right sides.
-- ignore_alpha sits above the raised pills' soft drop shadow (capped < 0.35)
-- and below every pill body (>= 0.5), so the shadow never frosts a halo of
-- wallpaper around the pill.
hl.layer_rule({
  name = "denon-frosted-bar",
  match = { namespace = "^inferna-bar$" },
  blur = true,
  ignore_alpha = 0.4,
  -- Pebble Shell seam: rail and frame are two layers; without xray the frame
  -- (stacked above) blurred the rail into its edge and came out darker there.
  -- Both blur only the wallpaper now, so they read as one surface.
  xray = true,
})

-- Pebble Shell (denon.shell): frost the rail + frame surface. Its fill is
-- >= 0.5 alpha; the rim and sheen sit on top of it, the hole is clear.
hl.layer_rule({
  name = "denon-frosted-shell",
  match = { namespace = "^denon-shell$" },
  blur = true,
  ignore_alpha = 0.4,
  -- Pebble Shell seam: rail and frame are two layers; without xray the frame
  -- (stacked above) blurred the rail into its edge and came out darker there.
  -- Both blur only the wallpaper now, so they read as one surface.
  xray = true,
})

-- Glass surfaces: frost every shell card (panels, menu, notifications, OSD,
-- polkit, clipboard, emojis, reminders). ignore_alpha sits between the scrims
-- and shadows (< 0.5) and the card fills (>= 0.74, set by glass-surfaces), so
-- only the cards themselves get blurred.
hl.layer_rule({
  name = "denon-frosted-surfaces",
  match = { namespace = "^((inferna|omarchy)-(menu|notifications|osd|polkit|clipboard|emojis|reminders|keyboard-panel|network-qr)|denon-bar-panel|softly)$" },
  blur = true,
  ignore_alpha = 0.5,
})

-- Pebble Shell: drawers and the menu attach to the rail/frame, so they
-- frost the wallpaper like the shell does (xray) instead of the window behind
-- them; otherwise each neck showed a tone step against the rail.
hl.layer_rule({
  name = "denon-shell-drawers",
  match = { namespace = "^(denon-bar-panel|inferna-menu)$" },
  xray = true,
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Glass controls: opacity, grain, and backdrop adjustments from the bar.
do local p = os.getenv("HOME") .. "/.config/hypr/glass.lua"; local f = io.open(p); if f then f:close(); dofile(p) end end

-- Glass surfaces: also frost xdg popups (tray menus and other bar flyouts that
-- open as popups); same 0.5 threshold so only the painted card blurs.
hl.config({ decoration = { blur = { popups = true, popups_ignorealpha = 0.5 } } })
