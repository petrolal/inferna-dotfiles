-- Keep only your personal input overrides here. Uncommented settings below
-- replace Omarchy's defaults.

-- Natural (macOS-style) trackpad scrolling.
-- hl.config({
--  input = {
--    -- Focus the window under the pointer.
--    follow_mouse = 1,
--    touchpad = {
--      natural_scroll = true,
--    },
--  },
-- })

-- Keyboard layout and options.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
   input = {
       -- Use multiple keyboard layouts and switch between them with Left Alt + Right Alt.
       kb_layout = "us",
       kb_options = "compose:caps,shift:both_capslock_cancel,grp:alts_toggle",

       -- Use a specific keyboard variant if needed (e.g. intl for international keyboards).
       kb_variant = "intl",

       -- Change speed of keyboard repeat.
       repeat_rate = 40,
       repeat_delay = 250,

       -- Start with numlock on by default.
       numlock_by_default = true,

       -- Increase sensitivity for mouse/trackpad (default: 0).
       sensitivity = 0.35,

       -- Turn off mouse acceleration (default: adaptive).
       accel_profile = "flat",

       touchpad = {
           -- Use natural (inverse) scrolling.
           natural_scroll = true,

           -- Use two-finger clicks for right-click instead of lower-right corner.
           clickfinger_behavior = true,

           -- Control the speed of your scrolling.
           scroll_factor = 0.4,

           -- Enable the touchpad while typing.
           disable_while_typing = false,

           -- Left-click-and-drag with three fingers.
           drag_3fg = 1,
       },
   },
})

-- App-specific touchpad scroll speeds.
-- o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
-- o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })

-- Three-finger swipes are handled by the Tricky Tiles plugin (its panel sets
-- follow-fingers or one-per-swipe, and wrap-around). The previous one-step
-- carousel swipes, kept for reference (Super+Left/Right still use carousel.lua):
-- -- One column per swipe, with a continuous carousel at either end of the row.
-- -- Keep natural direction: swipe left to reveal the window on the right.
-- local carousel = require("hypr.carousel")
-- hl.gesture({ fingers = 3, direction = "left", action = function()
--   carousel.step("r")
-- end })
-- hl.gesture({ fingers = 3, direction = "right", action = function()
--   carousel.step("l")
-- end })

-- -- Match horizontal window swipes: one workspace step on finger release.
-- -- Up goes to the next numbered workspace; down returns to the previous one.
-- -- No continuous drag distance, commit threshold, or fling momentum.
-- hl.gesture({ fingers = 3, direction = "up", action = function()
--   hl.dispatch(hl.dsp.focus({ workspace = "r+1" }))
-- end })
-- hl.gesture({ fingers = 3, direction = "down", action = function()
--   hl.dispatch(hl.dsp.focus({ workspace = "r-1" }))
-- end })

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Enable touchpad gestures for moving focus (helpful on scrolling layout).
-- hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end })
-- hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ direction = "r" })) end })

-- Touchpad bar controls: persisted pointer, scroll, and tap settings.
do local p = os.getenv("HOME") .. "/.config/hypr/touchpad-control.lua"; local f = io.open(p); if f then f:close(); dofile(p) end end

-- Four-finger Brave tab gestures (both horizontal and vertical).
require("hypr.brave-tabs")
