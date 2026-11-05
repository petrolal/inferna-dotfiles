#!/usr/bin/env python3
"""Validated, serialized touchpad settings for the Inferna bar plugin.

The generated Lua file is both persistent configuration and the source of UI
values. A single bounded .last-good file supports failed-change rollback.
"""

import fcntl
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile

def _find_touchpad():
    """This machine's touchpad name from Hyprland (override with TOUCHPAD_DEVICE)."""
    if os.environ.get("TOUCHPAD_DEVICE"):
        return os.environ["TOUCHPAD_DEVICE"]
    try:
        out = subprocess.run(["hyprctl", "devices", "-j"], text=True, capture_output=True, timeout=8).stdout
        names = [m.get("name", "") for m in json.loads(out).get("mice", [])]
        return next((n for n in names if "touchpad" in n.lower()), "")
    except Exception:
        return ""


DEVICE = _find_touchpad()
CONFIG = Path.home() / ".config/hypr/touchpad-control.lua"
LOCK = Path.home() / ".cache/touchpad-control.lock"
PREFIX = "-- touchpad-control-state: "
DEFAULTS = {
    "pointer": 0.0,
    "scroll": 0.4,
    "t3_scroll": 0.28,
    "tap_to_click": True,
    "tap_and_drag": True,
    "disable_while_typing": True,
    "drag_lock": 0,
}
RANGES = {"pointer": (-1.0, 1.0), "scroll": (0.1, 1.5), "t3_scroll": (0.1, 1.5)}
BOOL_KEYS = {"tap_to_click", "tap_and_drag", "disable_while_typing"}


def hypr(*args):
    result = subprocess.run(["hyprctl", *args], text=True, capture_output=True, timeout=8)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip() or "Hyprland command failed")
    return result.stdout.strip()


def validate(key, value):
    if key in RANGES:
        if isinstance(value, bool):
            raise ValueError(f"{key} requires a number")
        number = float(value)
        lo, hi = RANGES[key]
        if not math.isfinite(number) or not lo <= number <= hi:
            raise ValueError(f"{key} must be between {lo:g} and {hi:g}")
        return round(number, 4)
    if key in BOOL_KEYS:
        if str(value).lower() in ("true", "1"):
            return True
        if str(value).lower() in ("false", "0"):
            return False
        raise ValueError(f"{key} requires true or false")
    if key == "drag_lock":
        if str(value) not in ("0", "1", "2"):
            raise ValueError("drag_lock must be 0 (off), 1 (timeout), or 2 (sticky)")
        return int(value)
    raise ValueError("Unknown setting: " + key)


def read_values():
    if not CONFIG.exists():
        return dict(DEFAULTS)
    first = CONFIG.read_text().splitlines()[0]
    if not first.startswith(PREFIX):
        raise ValueError("The touchpad configuration was edited externally; expected state header is missing")
    raw = json.loads(first[len(PREFIX):])
    if set(raw) != set(DEFAULTS):
        raise ValueError("Unexpected settings in touchpad configuration")
    return {key: validate(key, value) for key, value in raw.items()}


def render(values):
    lines = [PREFIX + json.dumps(values, sort_keys=True),
             "-- Managed by ~/.local/share/touchpad-control/control.py; use the bar controls.",
             "-- Only this laptop's touchpad is changed. Mouse settings are preserved.",
             "hl.device({", '  name = "' + DEVICE + '",']
    names = {"pointer": "sensitivity", "scroll": "scroll_factor"}
    for key, value in values.items():
        if key == "t3_scroll":
            continue
        literal = str(value).lower() if isinstance(value, bool) else str(value)
        lines.append(f"  {names.get(key, key)} = {literal},")
    lines += ["})", "", "-- This is an absolute app scroll factor, not a multiplier.",
              'o.window("com[.]t3tools[.]T3Code", { scroll_touchpad = ' + str(values["t3_scroll"]) + " })",
              "-- Readback of configuration accepted by Lua; not a libinput hardware measurement.",
              "_G.touchpad_control_loaded = '" + json.dumps(values, sort_keys=True) + "'", ""]
    return "\n".join(lines)


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def config_errors():
    output = hypr("configerrors")
    return [] if not output else [output]


def accepted_config():
    raw = hypr("repl", 'return _G.touchpad_control_loaded or "null"')
    return json.loads(raw)


def snapshot(extra_errors=()):
    errors = list(extra_errors)
    values = dict(DEFAULTS)
    available = False
    runtime = None
    accepted = None
    try:
        values = read_values()
        devices = json.loads(hypr("devices", "-j"))
        runtime = next((item for item in devices.get("mice", []) if item.get("name") == DEVICE), None)
        available = runtime is not None
        errors.extend(config_errors())
        accepted = accepted_config()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        errors.append(str(exc))
    return {"ok": not errors, "available": available, "device": DEVICE,
            "values": values, "errors": errors, "initialized": CONFIG.exists(),
            "runtime": runtime, "accepted_config": accepted}


def initialize():
    # Parent installs the dofile include afterward, and then reloads Hyprland.
    if CONFIG.exists():
        read_values()
        return
    values = dict(DEFAULTS)
    for key in BOOL_KEYS | {"drag_lock"}:
        option = key.replace("_", "-") if key in ("tap_to_click", "tap_and_drag") else key
        data = json.loads(hypr("getoption", "-j", "input:touchpad:" + option))
        raw = data.get("bool", data.get("int"))
        if raw is None:
            raise RuntimeError("Could not read initial touchpad option " + key)
        values[key] = validate(key, raw)
    atomic_write(CONFIG, render(values))


def apply_setting(key, value):
    checked = validate(key, value)
    before = snapshot()
    if before["errors"]:
        raise RuntimeError("Fix existing configuration errors first: " + "; ".join(before["errors"]))
    if not before["available"]:
        raise RuntimeError("The laptop touchpad is not available")
    if not CONFIG.exists():
        raise RuntimeError("Touchpad controls are not installed yet")
    values = before["values"]
    if values[key] == checked:
        return
    original = CONFIG.read_text()
    values[key] = checked
    atomic_write(CONFIG.with_suffix(".lua.last-good"), original)
    atomic_write(CONFIG, render(values))
    try:
        hypr("reload")
        errors = config_errors()
        if errors:
            raise RuntimeError("; ".join(errors))
        # Confirm execution of every generated option, then independently check
        # the runtime scroll factor. Hyprctl devices.defaultSpeed is the hardware
        # DEFAULT speed, not current sensitivity; it must not be checked here.
        if accepted_config() != values:
            raise RuntimeError("Hyprland did not load the requested touchpad configuration; check the input.lua include")
        devices = json.loads(hypr("devices", "-j"))
        device = next(item for item in devices["mice"] if item["name"] == DEVICE)
        if abs(device["scrollFactor"] - values["scroll"]) > 0.011:
            raise RuntimeError("Hyprland did not apply the touchpad configuration; check the input.lua include")
    except (OSError, ValueError, KeyError, StopIteration, RuntimeError, subprocess.TimeoutExpired) as exc:
        atomic_write(CONFIG, original)
        try:
            hypr("reload")
            rollback_errors = config_errors()
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as rollback:
            rollback_errors = [str(rollback)]
        detail = "; rollback errors: " + "; ".join(rollback_errors) if rollback_errors else "; previous settings restored"
        raise RuntimeError(str(exc) + detail) from exc


def main():
    errors = []
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with LOCK.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            args = sys.argv[1:]
            if args == ["init"]:
                initialize()
            elif len(args) == 3 and args[0] == "set":
                apply_setting(args[1], args[2])
            elif args != ["state"]:
                raise ValueError("Usage: control.py state | init | set KEY VALUE")
        except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
            errors.append(str(exc))
        result = snapshot(errors)
    print(json.dumps(result, sort_keys=True))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
