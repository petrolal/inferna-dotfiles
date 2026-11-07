#!/usr/bin/env python3
"""Persistent Inferna glass controls, applied through a dedicated Hyprland file."""
import argparse
import datetime
import fcntl
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HOME = Path.home()
SETTINGS = HOME / '.config/inferna/glass.json'
LUA = HOME / '.config/hypr/glass.lua'
STATE = HOME / '.local/state/inferna-glass'
BASELINE = dict(enabled=True, light_readable=True, active=0.76, inactive=0.73, browser_active=0.84,
                browser_inactive=0.80, noise=0.0, size=6, contrast=1.0,
                brightness=1.0, vibrancy=0.1696)
LIMITS = dict(active=(0.4, 1), inactive=(0.4, 1), browser_active=(0.4, 1),
              browser_inactive=(0.4, 1), size=(1, 12),
              contrast=(0.5, 1.5), brightness=(0.6, 1.2), vibrancy=(0, 0.5))
USER_PRESETS = HOME / '.config/inferna/glass-presets.json'
LOOK_KEYS = ('active', 'inactive', 'browser_active', 'browser_inactive',
             'size', 'contrast', 'brightness', 'vibrancy')


def _p(active, inactive, browser_active, browser_inactive, size, contrast=1.0, brightness=1.0, vibrancy=0.17):
    return dict(active=active, inactive=inactive, browser_active=browser_active,
                browser_inactive=browser_inactive, size=size, contrast=contrast,
                brightness=brightness, vibrancy=vibrancy)


# Built-in looks (id, name, values). 'balanced', 'clear' and 'frosted' keep their
# original ids so older callers still work.
BUILTIN = [
    ('balanced', 'Balanced', _p(0.76, 0.73, 0.84, 0.80, 6, 1.0, 1.0, 0.1696)),
    ('clear', 'Clear', _p(0.90, 0.86, 0.96, 0.92, 6)),
    ('frosted', 'Frosted', _p(0.72, 0.68, 0.82, 0.78, 9)),
    ('crystal', 'Crystal', _p(0.82, 0.78, 0.92, 0.88, 2, 1.0, 1.0, 0.10)),
    ('ice', 'Ice', _p(0.70, 0.64, 0.80, 0.74, 11, 0.9, 1.10, 0.05)),
    ('mist', 'Mist', _p(0.66, 0.60, 0.78, 0.72, 12, 0.75, 1.05, 0.10)),
    ('ghost', 'Ghost', _p(0.55, 0.48, 0.70, 0.62, 12, 1.0, 1.0, 0.15)),
    ('smoke', 'Smoke', _p(0.78, 0.70, 0.86, 0.80, 8, 1.1, 0.75, 0.08)),
    ('midnight', 'Midnight', _p(0.84, 0.76, 0.90, 0.84, 10, 1.2, 0.65, 0.12)),
    ('noir', 'Noir', _p(0.82, 0.74, 0.88, 0.82, 9, 1.35, 0.70, 0.0)),
    ('aurora', 'Aurora', _p(0.70, 0.62, 0.80, 0.74, 8, 1.15, 1.0, 0.45)),
    ('vivid', 'Vivid', _p(0.74, 0.68, 0.84, 0.78, 7, 1.3, 1.0, 0.35)),
    ('bloom', 'Bloom', _p(0.68, 0.60, 0.80, 0.72, 10, 1.1, 1.08, 0.50)),
    ('pastel', 'Pastel', _p(0.76, 0.70, 0.84, 0.80, 10, 0.8, 1.12, 0.25)),
    ('sunlit', 'Sunlit', _p(0.86, 0.80, 0.92, 0.86, 9, 0.85, 1.18, 0.20)),
    ('studio', 'Studio', _p(0.80, 0.74, 0.88, 0.82, 7, 1.0, 1.0, 0.0)),
    ('focus', 'Focus', _p(0.95, 0.62, 0.97, 0.70, 9, 1.0, 1.0, 0.12)),
    ('reading', 'Reading', _p(0.94, 0.88, 0.97, 0.93, 8, 1.0, 0.90, 0.05)),
    ('cinema', 'Cinema', _p(0.88, 0.60, 0.92, 0.66, 12, 1.2, 0.70, 0.10)),
    ('solid', 'Nearly solid', _p(0.98, 0.96, 1.0, 0.98, 6, 1.0, 1.0, 0.10)),
]
PRESETS = {pid: dict(BASELINE, **vals) for pid, _, vals in BUILTIN}


def user_presets():
    try:
        data = json.loads(USER_PRESETS.read_text())
        return [p for p in data if isinstance(p, dict) and p.get('id') and p.get('name')]
    except Exception:
        return []


def write_user_presets(items):
    atomic(USER_PRESETS, json.dumps(items, indent=2) + '\n')


def all_presets():
    out = [dict(id=pid, name=name, builtin=True, values=vals) for pid, name, vals in BUILTIN]
    out += [dict(id=p['id'], name=p['name'], builtin=False,
                 values={k: p['values'][k] for k in LOOK_KEYS if k in p.get('values', {})})
            for p in user_presets()]
    return out


def find_preset(pid):
    for p in all_presets():
        if p['id'] == pid:
            return p
    raise ValueError('Unknown preset')


def look(values):
    return {k: values[k] for k in LOOK_KEYS}


def clean_name(name):
    name = ' '.join(str(name or '').split())[:40]
    if not name:
        raise ValueError('Give the preset a name')
    return name


def read():
    values = dict(BASELINE, **json.loads(SETTINGS.read_text())) if SETTINGS.exists() else dict(BASELINE)
    values['noise'] = 0.0
    return values


def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            out.write(text)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def theme_mode():
    try:
        r = subprocess.run(['inferna', 'theme', 'color', '--file',
                            str(HOME / '.local/state/inferna/current/theme/colors.toml'), 'mode'],
                           capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.stdout.strip() in ('light', 'dark') else 'dark'
    except Exception:
        return 'dark'


def for_mode(v, mode):
    """Light themes: whole-window opacity lets a dark/colourful wallpaper muddy pale
    surfaces and fades dark text, so keep only a hint of glass and brighten what shows
    through. Saved slider values are unchanged; dark themes use them as-is."""
    if mode != 'light' or not v.get('light_readable', True):
        return v
    v = dict(v)
    for k in ('active', 'inactive', 'browser_active', 'browser_inactive'):
        v[k] = round(1 - (1 - v[k]) * 0.25, 3)  # 80% -> 95%, 68% -> 92%
    v['brightness'] = round(min(1.2, max(v['brightness'], 1.0) * 1.15), 3)
    v['contrast'] = round(min(v['contrast'], 0.9), 3)
    v['vibrancy'] = round(min(v['vibrancy'], 0.08), 3)
    return v


def render(v):
    v = for_mode(v, theme_mode())
    lines = ['-- Generated by Glass controls. Edit using the bar panel.',
             'hl.config({ decoration = { blur = { enabled = true, passes = 2, noise = 0,']
    lines += [f'  {k} = {v[k]},' for k in ('size', 'contrast', 'brightness', 'vibrancy')]
    lines += ['} } })']
    for tag, a, i in [('default-opacity', 'active', 'inactive'),
                       ('chromium-based-browser', 'browser_active', 'browser_inactive'),
                       ('firefox-based-browser', 'browser_active', 'browser_inactive')]:
        active, inactive = (v[a], v[i]) if v['enabled'] else (1.0, 1.0)
        # Maximized windows use the fullscreen opacity channel too.
        for match, full in [('', 1.0), (', fullscreen_state_internal = 1', active),
                            (', fullscreen_state_internal = 1, focus = false', inactive)]:
            lines.append(f'o.window({{ tag = "{tag}"{match} }}, {{ opacity = "{active} override {inactive} override {full} override" }})')
    return '\n'.join(lines) + '\n'


def hypr(*args):
    r = subprocess.run(['hyprctl', *args], capture_output=True, text=True, timeout=15)
    if r.returncode:
        raise RuntimeError(r.stderr.strip() or r.stdout.strip() or 'Hyprland command failed')
    return r.stdout.strip()


def apply(values):
    old = {p: p.read_text() if p.exists() else None for p in (SETTINGS, LUA)}
    before = hypr('configerrors')
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = STATE / 'backups' / stamp
    backup.mkdir(parents=True)
    for p in old:
        if p.exists():
            shutil.copy2(p, backup / p.name)
    try:
        atomic(LUA, render(values))
        hypr('reload', 'config-only')
        errors = hypr('configerrors')
        if errors and errors != before:
            raise RuntimeError(errors)
        atomic(SETTINGS, json.dumps(values, indent=2) + '\n')
    except Exception:
        for p, text in old.items():
            if text is not None:
                atomic(p, text)
            elif p.exists():
                p.unlink()
        hypr('reload', 'config-only')
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['state', 'set', 'preset', 'reset', 'apply',
                                           'save-preset', 'update-preset', 'rename-preset', 'delete-preset'])
    parser.add_argument('key', nargs='?')
    parser.add_argument('value', nargs='?')
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        values = read()
        try:
            if args.action == 'set':
                if args.key in ('enabled', 'light_readable'):
                    if args.value not in ('true', 'false'):
                        raise ValueError('Expected true or false')
                    values[args.key] = args.value == 'true'
                else:
                    if args.key not in LIMITS:
                        raise ValueError('Unknown setting')
                    value = float(args.value)
                    lo, hi = LIMITS[args.key]
                    if not math.isfinite(value) or not lo <= value <= hi:
                        raise ValueError('Value outside the slider range')
                    values[args.key] = int(round(value)) if args.key == 'size' else round(value, 4)
            elif args.action == 'preset':
                values = dict(values, **find_preset(args.key)['values'])
                values['preset'] = args.key
            elif args.action == 'reset':
                values = dict(BASELINE, enabled=values.get('enabled', True), preset='balanced')
            elif args.action == 'save-preset':
                name = clean_name(args.key)
                items = user_presets()
                pid = 'user-' + datetime.datetime.now().strftime('%Y%m%d%H%M%S%f')
                items.append(dict(id=pid, name=name, values=look(values)))
                write_user_presets(items)
                values['preset'] = pid
            elif args.action in ('update-preset', 'rename-preset', 'delete-preset'):
                items = user_presets()
                match = [p for p in items if p['id'] == args.key]
                if not match:
                    raise ValueError('Built-in presets cannot be changed' if args.key in PRESETS else 'Unknown preset')
                if args.action == 'update-preset':
                    match[0]['values'] = look(values)
                    values['preset'] = args.key
                elif args.action == 'rename-preset':
                    match[0]['name'] = clean_name(args.value)
                else:
                    items = [p for p in items if p['id'] != args.key]
                    if values.get('preset') == args.key:
                        values.pop('preset', None)
                write_user_presets(items)
            if args.action not in ('state', 'rename-preset'):
                apply(values)
            print(json.dumps(dict(ok=True, values=values, preset=values.get('preset', ''),
                                  presets=all_presets())))
        except Exception as exc:
            print(json.dumps(dict(ok=False, error=str(exc), values=read(), presets=all_presets())))
            raise SystemExit(1)


if __name__ == '__main__':
    main()
