-- Four-finger tab switching, restricted to normal Brave browser windows.
-- Web apps (brave-<site>-Default) intentionally keep their own input behavior.
local tabs = {}
local browser_classes = {
  ["brave-browser"] = true,
  ["brave-browser-beta"] = true,
  ["brave-browser-nightly"] = true,
  ["brave"] = true,
}

function tabs.step(direction)
  if direction ~= "next" and direction ~= "previous" then return end
  local window = hl.get_active_window()
  if not window or not browser_classes[window.class:lower()] then return end
  hl.dispatch(hl.dsp.send_shortcut({
    mods = direction == "next" and "CTRL" or "CTRL SHIFT",
    key = "Tab",
    window = "address:" .. window.address,
  }))
end

-- Unset defaults if present
pcall(hl.gesture, { fingers = 4, direction = "left", action = "unset" })
pcall(hl.gesture, { fingers = 4, direction = "right", action = "unset" })
pcall(hl.gesture, { fingers = 4, direction = "down", action = "unset" })

for _, direction in ipairs({ "left", "up" }) do
  hl.gesture({ fingers = 4, direction = direction, action = function()
    tabs.step("next")
  end })
end
for _, direction in ipairs({ "right", "down" }) do
  hl.gesture({ fingers = 4, direction = direction, action = function()
    tabs.step("previous")
  end })
end

return tabs
