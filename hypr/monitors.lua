-- monitors.lua --- display detection and layout
-- License: GPL-3.0-or-later

-- Laptop display (eDP-1): 1920x1080 @ 165Hz (native 1:1 scale for sharp crisp proportions)
hl.monitor({
    output   = "eDP-1",
    mode     = "preferred",
    position = "auto-right",
    scale    = 1,
})

-- External HDMI monitor (HDMI-A-1): 1920x1080 @ 60Hz
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "preferred",
    position = "0x0",
    scale    = 1,
})

-- Fallback for any other display: auto-detect and place
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- Keep GTK UI at 1:1 scale for 1080p displays (prevents bloated double-size UI)
hl.env("GDK_SCALE", "1")
