-- Inferno's own window-border tokens: a brighter, thicker border so tiled
-- windows read clearly against the theme's near-black wallpapers, instead of
-- the muted accent this would otherwise inherit from the shell template.
local active_border_color = { colors = { "rgba(ff6a5cff)", "rgba(fff7f2ff)" }, angle = 45 }
local inactive_border_color = "rgba(7d6360b3)"

hl.config({
  general = {
    border_size = 3,

    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },
})
