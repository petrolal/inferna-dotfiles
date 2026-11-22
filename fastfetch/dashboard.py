#!/usr/bin/env python3
"""Responsive system showcase for GNOME on NixOS, rendered with live Fastfetch data."""

import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path.home() / ".config/fastfetch"
BRAND = "INFERNA"

ACCENT_PALETTE = {
    "blue": "#3584e4",
    "teal": "#2190a4",
    "green": "#3a944a",
    "yellow": "#c88800",
    "orange": "#ed5b00",
    "red": "#e62d42",
    "pink": "#d56199",
    "purple": "#9141ac",
    "slate": "#6f8396",
}


def run(args, fallback=""):
    try:
        return subprocess.check_output(
            args, text=True, stderr=subprocess.DEVNULL, timeout=2
        ).strip()
    except (OSError, subprocess.SubprocessError):
        return fallback


def gsettings_get(schema, key, fallback=""):
    val = run(["gsettings", "get", schema, key], "")
    return val.strip().strip("'") if val else fallback


accent_name = gsettings_get("org.gnome.desktop.interface", "accent-color", "blue")
color_scheme = gsettings_get("org.gnome.desktop.interface", "color-scheme", "default")
accent_hex = ACCENT_PALETTE.get(accent_name, "#3584e4")


def color(hex_val):
    value = hex_val.lstrip("#")
    try:
        return "\033[38;2;{};{};{}m".format(
            *[int(value[i : i + 2], 16) for i in (0, 2, 4)]
        )
    except ValueError:
        return "\033[39m"


A = color(accent_hex)
C = color("#f2a949")
F = color("#f2e5d5")
M = color("#a69085")
G = color("#6ea862")
R = "\033[0m"
B = "\033[1m"

ansi = re.compile(r"\x1b\[[0-9;]*m")


def width(s):
    return len(ansi.sub("", s))


def pad(s, n):
    return s + " " * max(0, n - width(s))


def clip(s, n):
    return str(s) if len(str(s)) <= n else str(s)[: max(0, n - 1)] + "…"


cols = shutil.get_terminal_size((120, 40)).columns
try:
    with open("/dev/tty") as tty:
        cols = os.get_terminal_size(tty.fileno()).columns
except OSError:
    pass
if "--width" in sys.argv:
    cols = int(sys.argv[sys.argv.index("--width") + 1])
cols = max(40, cols - 2)

modules = "os:host:cpu:gpu:memory:swap:cpuusage:disk:netio:display:terminal:terminalfont:wm:packages:uptime:processes:loadavg:battery:kernel:board:bios:theme:icons:cursor"
try:
    result = subprocess.run(
        ["fastfetch", "--config", "none", "--structure", modules, "--format", "json"],
        capture_output=True,
        text=True,
        timeout=12,
        check=True,
    )
    data = {x["type"].lower(): x.get("result") for x in json.loads(result.stdout)}
except (subprocess.SubprocessError, ValueError) as e:
    print("Dashboard data unavailable:", e)
    sys.exit(1)


def d(k):
    return data.get(k) or {}


def first(k):
    return next(iter(data.get(k) or []), {})


def size(n):
    return f"{n / 1024**3:.1f} GiB"


def rate(n):
    return f"{n / 1024:.1f} KiB/s"


cpu = d("cpu")
gpu = first("gpu")
mem = d("memory")
swap = d("swap")
disk = next((x for x in data.get("disk", []) if x["mountpoint"] == "/"), {})
net = first("netio")
bat = first("battery")
display = first("display")
wm = d("wm")
kernel = d("kernel")
up = int(d("uptime").get("uptime", 0) / 1000)
proc = d("processes")
usage = data.get("cpuusage") or [0]
cores = cpu.get("cores", {})
bar_len = max(16, min(36, cols - 65)) if cols >= 75 else 16


def meter(p, blen=bar_len):
    p = max(0, min(100, float(p)))
    filled = round(p / 100 * blen)
    return C + "━" * filled + M + "─" * (blen - filled) + F + f" {p:4.0f}%"


def resource(key):
    v = d(key)
    if isinstance(v, list):
        v = {k: sum(x.get(k, 0) for x in v) for k in ("total", "used")}
    total = v.get("total", 0)
    used = v.get("used", 0)
    return meter(used / total * 100 if total else 0), f"{size(used)} / {size(total)}"


hardware = [
    ("Model", d("host").get("name", "")),
    ("Processor", cpu.get("cpu", "")),
    (
        "Topology",
        f"{cores.get('physical', '?')} cores / {cores.get('logical', '?')} threads",
    ),
    ("Boost", f"{cpu.get('frequency', {}).get('max', 0) / 1000:.2f} GHz"),
    ("Graphics", gpu.get("name", "")),
    ("GPU driver", gpu.get("driver", "")),
    (
        "Display",
        f"{display.get('output', {}).get('width', '?')} × {display.get('output', {}).get('height', '?')}  /  {display.get('output', {}).get('refreshRate', 0):.0f} Hz",
    ),
    ("Board", d("board").get("name", "")),
    ("Firmware", d("bios").get("version", "")),
]

ram_meter, ram_size = resource("memory")
swap_meter, swap_size = resource("swap")
db = disk.get("bytes", {})
total = db.get("total", 1)
used = total - db.get("free", total)

telemetry = [
    ("CPU", meter(sum(usage) / len(usage))),
    ("Memory", ram_meter),
    ("Allocated", ram_size),
    ("Swap", swap_meter),
    ("Swap used", swap_size),
    ("Root disk", meter(used / total * 100)),
    ("Capacity", f"{size(used)} / {size(total)}"),
    ("Filesystem", disk.get("filesystem", "")),
    ("Processes", f"{proc.get('processes', '?')} / {proc.get('threads', '?')} threads"),
    ("Load avg", "  ".join(f"{x:.2f}" for x in (data.get("loadavg") or []))),
    (
        "Battery",
        f"{bat.get('capacity', 0):.0f}%  /  {', '.join(bat.get('status', []))}",
    ),
]

system = [
    ("Distribution", f"{BRAND} · NixOS"),
    ("Kernel", kernel.get("release", "")),
    ("Architecture", kernel.get("architecture", "")),
    ("Uptime", f"{up // 86400}d {up % 86400 // 3600}h {up % 3600 // 60}m"),
    ("Packages", str(d("packages").get("all", "?"))),
    ("Session", wm.get("protocolName", "")),
    ("Snapshot", datetime.now().strftime("%H:%M:%S  /  %d %b %Y")),
]

# Detect parent terminal emulator
terminal_name = ""
pid = os.getpid()
for _ in range(32):
    try:
        comm = Path(f"/proc/{pid}/comm").read_text().strip()
        clean = comm.lstrip(".").removesuffix("-wrapped")
        if clean in (
            "kgx",
            "ptyxis",
            "gnome-terminal-server",
            "gnome-terminal",
            "wezterm-gui",
            "xterm",
        ):
            terminal_name = clean
            break
        status = Path(f"/proc/{pid}/status").read_text()
        pid = int(re.search(r"^PPid:\s+(\d+)", status, re.M).group(1))
        if pid <= 1:
            break
    except (OSError, AttributeError, ValueError):
        break

terminal_labels = {
    "kgx": "GNOME Console",
    "gnome-terminal-server": "GNOME Terminal",
    "gnome-terminal": "GNOME Terminal",
    "ptyxis": "Ptyxis",
}
terminal_label = terminal_labels.get(terminal_name, terminal_name) or "not detected"

font_label = "terminal default"
mono = gsettings_get("org.gnome.desktop.interface", "monospace-font-name", "")
if mono:
    parts = mono.rsplit(" ", 1)
    font_label = (
        f"{parts[0]} / {parts[1]}pt"
        if len(parts) == 2 and parts[1].replace(".", "", 1).isdigit()
        else mono
    )

gtk_theme = gsettings_get("org.gnome.desktop.interface", "gtk-theme", "") or d(
    "theme"
).get("theme2", "")
icon_theme = gsettings_get("org.gnome.desktop.interface", "icon-theme", "") or d(
    "icons"
).get("icons2", "")
cursor_theme = gsettings_get("org.gnome.desktop.interface", "cursor-theme", "") or d(
    "cursor"
).get("theme", "")
appearance = f"{color_scheme} / {accent_name}"

desktop = [
    ("Desktop", "GNOME"),
    ("Compositor", (wm.get("prettyName", "") + " " + wm.get("version", "")).strip()),
    ("Appearance", appearance),
    ("Terminal", terminal_label),
    ("Font", font_label),
    ("Shell", Path(os.environ.get("SHELL", "bash")).name),
    ("GTK", gtk_theme),
    ("Icons", icon_theme),
    ("Cursor", cursor_theme),
]

network = [
    ("Interface", net.get("name", "offline")),
    ("Receive", rate(net.get("rxBytes", 0))),
    ("Transmit", rate(net.get("txBytes", 0))),
    ("RX / TX drops", f"{net.get('rxDrops', 0)} / {net.get('txDrops', 0)}"),
]


def card(title, rows, w):
    inner = w - 4
    lines = [
        A + "╭─ " + B + title + R + A + " " + "─" * max(0, w - len(title) - 5) + "╮" + R
    ]
    for key, value in rows:
        if not value:
            continue
        if "\033" in str(value):
            content = C + f"{key:<14} " + F + str(value)
        else:
            content = C + f"{key:<14} " + F + clip(value, inner - 15)
        lines.append(A + "│ " + pad(content, inner) + A + " │" + R)
    lines.append(A + "╰" + "─" * (w - 2) + "╯" + R)
    return lines


logo_path = ROOT / "about.txt"
logo = logo_path.read_text().splitlines() if logo_path.exists() else [BRAND]

print()
heading = " ".join(BRAND.upper()) + "   /   GNOME"
print(B + A + heading + R)
subtitle = "SYSTEM OVERVIEW   ·   HARDWARE / TELEMETRY / DESKTOP"
print(M + clip(subtitle, cols) + R)
print(M + "━" * cols + R)
print()
for line in logo:
    print(A + line + R)
print()
for title, rows in [
    ("HARDWARE", hardware),
    ("LIVE TELEMETRY", telemetry),
    ("SYSTEM", system),
    ("DESKTOP", desktop),
    ("NETWORK", network),
]:
    print("\n".join(card(title, rows, cols)))
    print()
print()
print(M + "─" * cols + R)
print(
    G
    + "● "
    + F
    + "SYSTEM ONLINE"
    + M
    + "   /   GNOME   /   LIVE DATA · CAPTURED ON RUN"
    + R
)
print()
