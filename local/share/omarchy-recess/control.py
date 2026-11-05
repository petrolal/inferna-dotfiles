#!/usr/bin/python3
"""Depth settings: recessed or raised window frames, applied through a generated Hyprland module."""
import argparse
import fcntl
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile

HOME = Path.home()
SETTINGS = HOME / '.config/inferna/recess.json'
LUA = HOME / '.config/hypr/recessed_windows.lua'
STATE = HOME / '.local/state/inferna-recess'

# Two styles share one set of slider keys:
#   recessed: windows pressed into the screen (inner shade, dark top cut, lit lower lip)
#   raised:   windows lifted off it like pebbles (drop shadow, top sheen, convex inner light)
# Each style keeps a light and a dark profile; the active theme picks one at reload.
STYLES = ('recessed', 'raised')
PROFILES = ('light', 'dark')
LIMITS = dict(win_depth=(0, 1), win_soft=(2, 30), win_light=(0, 1), win_lip=(0, 1))
INTEGER = {'win_soft'}

# A profile is a look scaled by intensity (50 = the look as designed, 0 = flat,
# 100 = twice as strong). Moving a Details slider turns the look into "custom".
def _look(ld, ls, ll, lp, dd, ds, dl, dp):
    return dict(light=dict(win_depth=ld, win_soft=ls, win_light=ll, win_lip=lp),
                dark=dict(win_depth=dd, win_soft=ds, win_light=dl, win_lip=dp))


LOOKS = {
    'recessed': {
        'subtle': _look(0.28, 8, 0.25, 0.35, 0.5, 10, 0.25, 0.35),
        'carved': _look(0.45, 10, 0.3, 0.5, 0.7, 12, 0.3, 0.5),
        'deep': _look(0.75, 16, 0.4, 0.7, 0.95, 18, 0.4, 0.7),
    },
    'raised': {
        'soft': _look(0.35, 12, 0.35, 0.5, 0.45, 12, 0.35, 0.45),
        'pebble': _look(0.55, 16, 0.4, 0.7, 0.7, 16, 0.4, 0.65),
        'lifted': _look(0.8, 22, 0.5, 0.85, 0.9, 20, 0.5, 0.8),
    },
}
DEFAULT_LOOK = dict(recessed='carved', raised='pebble')

LUA_BODY = r'''
-- Theme-following: shadows and the lower lip adapt to light and dark themes.
local palette = ""
local file = io.open(os.getenv("HOME") .. "/.local/state/inferna/current/theme/colors.toml")
if file then palette = file:read("a"); file:close() end
local mode = palette:match('mode%s*=%s*"(.-)"')
local bg = palette:match('\nbackground%s*=%s*"#(%x%x%x%x%x%x)"') or palette:match('^background%s*=%s*"#(%x%x%x%x%x%x)"')
local light = mode == "light"
if not mode and bg then
  local r, g, b = tonumber(bg:sub(1, 2), 16), tonumber(bg:sub(3, 4), 16), tonumber(bg:sub(5, 6), 16)
  light = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.55
end

local P = light and S.light or S.dark

local function rgba(rgb, a)
  return string.format("rgba(%s%02x)", rgb, math.floor(math.max(0, math.min(1, a)) * 255 + 0.5))
end
local function vertical(top, middle, bottom) return { colors = { top, middle, bottom }, angle = 90 } end
local function grad(...) return { colors = { ... }, angle = 90 } end

if not S.enabled then return end

if S.style == "raised" then
  -- Raised (pebble), built in three layers the way physical buttons read:
  --  1. outline   the border is a dark contour that separates the pane from
  --               the wallpaper (darker at the bottom, where it turns away);
  --  2. rim       a short inner glow rolls light off the edge all the way
  --               around the pane: brightest on top, about half down the sides,
  --               neutral at the bottom. "Light from above" sets how far it
  --               wraps (1 = top only, 0 = evenly around, bottom included);
  --               softness sets how rounded the edge feels (crisp → cushion);
  --  3. lift      a soft drop shadow, tucked slightly under the pane and
  --               weighted toward the bottom so light reads as from above.
  -- A bright line on the outer border blends into a light wallpaper, so the
  -- highlight must live inside the edge, against the window's own body.
  local h, soft, sun, sheen = P.win_depth, P.win_soft, P.win_light, P.win_lip
  local o = light and (0.05 + 0.14 * h) or (0.12 + 0.32 * h)        -- outline
  local s = sheen * (light and 1.0 or 0.85)                          -- bevel light
  local b = (light and (0.04 + 0.12 * h) or (0.1 + 0.3 * h)) * (0.6 + 0.4 * sun)  -- bevel shade
  local lift = h * (light and 0.36 or 0.8)                           -- drop shadow
  local function outline(k)
    return grad(rgba("000000", o * 0.95 * k), rgba("000000", o * k), rgba("000000", o * 1.25 * k), rgba("000000", o * 1.6 * k))
  end
  local top_only = { 1, 0.29, 0.07, 0, 0, 0 }
  local wrapped = { 1, 0.8, 0.7, 0.66, 0.62, 0.58 }
  local function bevel(k)
    local stops = {}
    for i = 1, 6 do stops[i] = rgba("ffffff", s * (top_only[i] * sun + wrapped[i] * (1 - sun)) * k) end
    local bottom = s * 0.3 * (1 - sun) - b * sun     -- lit lip when wrapped, shade when lit from above
    stops[7] = bottom >= 0 and rgba("ffffff", bottom * k) or rgba("000000", -bottom * k)
    return { colors = stops, angle = 90 }
  end
  local function shade(k)
    return grad(rgba("000000", lift * (0.65 - 0.35 * sun) * k), rgba("000000", lift * 0.8 * k), rgba("000000", lift * k))
  end
  hl.config({
    general = { border_size = 1, col = { active_border = outline(1), inactive_border = outline(0.8) } },
    group = { col = { border_active = outline(1), border_inactive = outline(0.8) } },
    decoration = {
      shadow = { enabled = true, range = math.floor(soft * 1.6 + 0.5), render_power = 3, scale = 0.98,
                 offset = { 0, math.floor(soft * (0.2 + 0.35 * sun) + 0.5) },
                 color = shade(1), color_inactive = shade(0.7) },
      glow = { enabled = true, range = 2 + math.floor(soft * 0.3 + 0.5), render_power = 3,
               color = bevel(1), color_inactive = bevel(0.65) },
    },
  })
  return
end

-- Recessed. Light from above: 0 keeps the recess even on all four sides, 1 shades only the top.
-- Near-black compensation: smoothstep on weighted sRGB brightness, from no
-- adjustment at 0.12 to full at 0.035. Keep in sync with the panel and bar.
local function brightness(hex)
  return (0.2126 * tonumber(hex:sub(1, 2), 16) + 0.7152 * tonumber(hex:sub(3, 4), 16) + 0.0722 * tonumber(hex:sub(5, 6), 16)) / 255
end
local t = not light and bg and math.max(0, math.min(1, (0.12 - brightness(bg)) / 0.085)) or 0
local night = t * t * (3 - 2 * t)
local fg = palette:match('\nforeground%s*=%s*"#(%x%x%x%x%x%x)"') or palette:match('^foreground%s*=%s*"#(%x%x%x%x%x%x)"') or "ffffff"
local channels = {}
for i = 1, 3 do
  local c = tonumber(fg:sub(i * 2 - 1, i * 2), 16)
  channels[i] = string.format("%02x", math.floor(255 + (c - 255) * night + 0.5))
end
local lip_rgb = table.concat(channels)
-- Tighten the shade instead of spreading more black across an already black
-- face. Only the lower border catches extra light; there is no outer halo.
local shade = light and 0.45 or (0.85 + 0.1 * night)
local glint = light and 0.85 or (0.2 + 0.16 * night)
local soft = math.max(2, math.floor(P.win_soft * (1 - 0.35 * night) + 0.5))
local function inset(scale)
  local a = P.win_depth * shade * scale
  return vertical(rgba("000000", a), rgba("000000", a * (1 - P.win_light * 0.5)), rgba("000000", a * (1 - P.win_light)))
end
-- Border: a dark cut along the top fading to a lit lower lip.
local function edge(scale)
  local a = P.win_depth * shade * scale
  local lip = P.win_lip * glint * scale
  if night == 0 then
    return vertical(rgba("000000", a * 0.85), rgba("000000", a * 0.15), rgba("ffffff", lip))
  end
  -- Preserve the black upper cut; light reaches only the lower side walls
  -- and bottom. Five equally spaced stops keep the shoulder restrained.
  return grad(rgba("000000", a * 0.85), rgba("000000", a * (0.5 + 0.15 * night)),
              rgba("000000", a * 0.15), rgba(lip_rgb, lip * (0.5 + 0.1 * night)), rgba(lip_rgb, lip))
end

hl.config({
  general = { border_size = 1, col = { active_border = edge(1), inactive_border = edge(0.75) } },
  group = { col = { border_active = edge(1), border_inactive = edge(0.75) } },
  decoration = {
    shadow = { enabled = false },
    glow = { enabled = true, range = soft, render_power = 2, color = inset(1), color_inactive = inset(0.75) },
  },
})
'''


def clamp(key, value):
    lo, hi = LIMITS[key]
    value = max(lo, min(hi, float(value)))
    return int(round(value)) if key in INTEGER else round(value, 3)


def fresh(style):
    look = DEFAULT_LOOK[style]
    return {name: dict(LOOKS[style][look][name], look=look, intensity=50) for name in PROFILES}


def load_profile(target, saved, style, name):
    """Merge one saved profile, recognising older settings without a look."""
    if not isinstance(saved, dict):
        return
    target.update({k: clamp(k, v) for k, v in saved.items() if k in LIMITS})
    if saved.get('look') in tuple(LOOKS[style]) + ('custom',):
        target['look'] = saved['look']
        target['intensity'] = int(max(0, min(100, float(saved.get('intensity', 50)))))
    else:
        target['look'] = next((i for i in LOOKS[style] if all(
            abs(target[k] - LOOKS[style][i][name][k]) < 1e-6 for k in LIMITS)), 'custom')


def read():
    try:
        saved = json.loads(SETTINGS.read_text())
    except (OSError, ValueError):
        saved = {}
    values = dict(enabled=True, style='recessed', styles={style: fresh(style) for style in STYLES})
    if 'enabled' in saved:
        # Shared-container mode was removed; "container only" meant no window recess.
        values['enabled'] = bool(saved['enabled']) and saved.get('mode') != 'container'
    if saved.get('style') in STYLES:
        values['style'] = saved['style']
    # Before styles existed, "profiles" held the recessed settings.
    styles = saved.get('styles') or {'recessed': saved.get('profiles') or {}}
    for style in STYLES:
        for name, profile in (styles.get(style) or {}).items():
            if name in PROFILES:
                load_profile(values['styles'][style][name], profile, style, name)
    return values


def scaled(style, look, profile, intensity):
    """Effective sliders for a look at an intensity (50 = as designed)."""
    base, k = LOOKS[style][look][profile], intensity / 50
    return dict(win_depth=clamp('win_depth', base['win_depth'] * k),
                win_soft=clamp('win_soft', base['win_soft'] * (0.5 + 0.5 * k)),
                win_light=base['win_light'],
                win_lip=clamp('win_lip', base['win_lip'] * k))


def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            out.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def render(v):
    def table(profile):
        return '{ ' + ', '.join(f'{k} = {profile[k]}' for k in LIMITS) + ' }'
    active = v['styles'][v['style']]
    head = ('-- Generated by the Depth plugin (denon.recess). Adjust from its bar panel.\n'
            f'local S = {{ enabled = {str(v["enabled"]).lower()}, style = "{v["style"]}",\n'
            f'  light = {table(active["light"])},\n  dark = {table(active["dark"])} }}\n')
    return head + LUA_BODY


def theme_profile():
    """'light' or 'dark' for the active theme, matching the Lua module's test."""
    try:
        text = (HOME / '.local/state/inferna/current/theme/colors.toml').read_text()
    except OSError:
        return 'dark'
    mode = re.search(r'^mode\s*=\s*"(\w+)"', text, re.M)
    if mode:
        return 'light' if mode.group(1) == 'light' else 'dark'
    bg = re.search(r'^background\s*=\s*"#([0-9a-fA-F]{6})"', text, re.M)
    if not bg:
        return 'dark'
    r, g, b = (int(bg.group(1)[i:i + 2], 16) for i in (0, 2, 4))
    return 'light' if (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.55 else 'dark'


def hypr(*args):
    r = subprocess.run(['hyprctl', *args], capture_output=True, text=True, timeout=15)
    if r.returncode:
        raise RuntimeError(r.stderr.strip() or r.stdout.strip() or 'Hyprland command failed')
    return r.stdout.strip()


def save(values):
    old_lua = LUA.read_text() if LUA.exists() else None
    if old_lua != render(values):
        before = hypr('configerrors')
        atomic(LUA, render(values))
        try:
            hypr('reload', 'config-only')
            errors = hypr('configerrors')
            if errors and errors != before:
                raise RuntimeError(errors)
        except Exception:
            if old_lua is not None:
                atomic(LUA, old_lua)
            hypr('reload', 'config-only')
            raise
    atomic(SETTINGS, json.dumps(values, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['state', 'set', 'preset', 'reset', 'apply'])
    parser.add_argument('key', nargs='?')
    parser.add_argument('value', nargs='?')
    parser.add_argument('--profile', choices=PROFILES, default='light',
                        help='theme profile for slider keys and looks')
    parser.add_argument('--style', choices=STYLES, help='style to edit (default: the active one)')
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        values = read()
        try:
            style = args.style or values['style']
            target = values['styles'][style][args.profile]
            if args.action == 'set':
                if args.key == 'enabled':
                    values['enabled'] = args.value in ('1', 'true', 'on')
                elif args.key == 'style':
                    if args.value not in STYLES:
                        raise ValueError(f'style must be one of {", ".join(STYLES)}')
                    values['style'] = args.value
                elif args.key in LIMITS:
                    target[args.key] = clamp(args.key, args.value)
                    target['look'] = 'custom'
                elif args.key == 'intensity':
                    if target['look'] not in LOOKS[style]:
                        raise ValueError('pick a look before setting intensity')
                    target['intensity'] = int(max(0, min(100, float(args.value))))
                    target.update(scaled(style, target['look'], args.profile, target['intensity']))
                else:
                    raise ValueError(f'unknown setting {args.key}')
                save(values)
            elif args.action == 'preset':
                if args.key not in LOOKS[style]:
                    raise ValueError(f'unknown look {args.key} for {style}')
                target['look'] = args.key
                target.update(scaled(style, args.key, args.profile, target.get('intensity', 50)))
                save(values)
            elif args.action == 'reset':
                values['styles'][style][args.profile] = fresh(style)[args.profile]
                save(values)
            elif args.action == 'apply':
                save(values)
            print(json.dumps(dict(ok=True, values=values, theme=theme_profile(), looks=LOOKS)))
        except Exception as error:  # report to the panel instead of a traceback
            print(json.dumps(dict(ok=False, error=str(error), values=values, theme=theme_profile(), looks=LOOKS)))
            raise SystemExit(1)


if __name__ == '__main__':
    main()
