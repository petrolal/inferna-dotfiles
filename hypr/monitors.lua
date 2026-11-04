-- monitors.lua --- display detection and layout
-- License: GPL-3.0-or-later

-- Laptop display (eDP-1): 1920x1080 @ 165Hz
hl.monitor({
    output   = "eDP-1",
    mode     = "preferred",
    position = "0x0",
    scale    = 1.5,
})

-- External HDMI monitor (HDMI-A-1): 1920x1080 @ 60Hz
-- Positioned at 1280x0 (adjacent to eDP-1 at 1.5 scale)
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "preferred",
    position = "1280x0",
    scale    = 1,
})

-- Fallback for any other display: auto-detect and place
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})
