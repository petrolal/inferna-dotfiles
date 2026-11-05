---
name: inferna
description: >
  REQUIRED for end-user customization of Linux desktop, window manager, or system config.
  Use when editing ANY file in ~/.config/, ~/.config/hypr/, ~/.config/inferna/,
  ~/.config/alacritty/, ~/.config/foot/, ~/.config/kitty/, or ~/.config/ghostty/.
  Triggers: Hyprland, window rules, window behavior, animations, keybindings, monitors, gaps, borders,
  blur, opacity, inferna-shell, bar, widgets, terminal config, themes, fonts, background,
  night light, idle, lock screen, screenshots, screen recording, reminders, layer rules, workspace
  settings, display config, appearance changes, and user-facing omarchy commands. Excludes Inferna
  source development through `omarchy dev link` workflows.
---

# Inferna Skill

Manage [Inferna](https://omarchy.org/) Linux systems - a beautiful, fun, agentic Arch Linux distribution with Hyprland.

This skill is for end-user customization on installed systems.
It is not for contributing to Inferna source code.

## Topic Guides

Deeper instructions for common areas live next to this file. Read the
matching guide before starting:

- [`hyprland.md`](hyprland.md) - keybindings, monitors, window rules, and other Hyprland config
- [`plugins.md`](plugins.md) - the Inferna shell: bar layout, widgets, plugins, idle behavior
- [`theming.md`](theming.md) - themes, backgrounds, and fonts
- [`hooks.md`](hooks.md) - automation hooks that run on system events
- [`capture.md`](capture.md) - screenshots, screen recordings, OCR text capture, and file sharing
- [`contributing.md`](contributing.md) - reporting Inferna bugs and submitting fixes upstream

## Critical Safety Rules

For privileged commands, follow the Privilege Escalation rules below: `sudo` when a terminal is available for the password prompt, `pkexec` when it is not. Do not wrap commands that already manage privilege elevation themselves.

**For end-user customization tasks, NEVER modify anything in `/usr/share/omarchy/`** - but READING is safe and encouraged.

This directory is owned by the inferna package. Any local changes will be
overwritten on the next `inferna update`.

```
/usr/share/omarchy/     # READ-ONLY - NEVER EDIT (reading is OK)
├── bin/                    # Command source (packaged binaries are on PATH)
├── config/                 # Default config templates
├── themes/                 # Stock themes
├── default/                # System defaults
├── shell/                  # Inferna shell source and defaults
├── migrations/             # Update migrations
└── install/                # Installation scripts
```

**Reading `/usr/share/omarchy/` is SAFE and useful** - do it freely to:
- Understand how omarchy commands work: `inferna theme set --help` or `cat $(which inferna-theme-set)`
- See default configs before customizing: `cat "$OMARCHY_PATH/config/omarchy/shell.json"`
- Check stock theme files to copy for customization
- Reference default hyprland settings: `cat /usr/share/omarchy/default/hypr/*`

**Always use these safe locations instead:**
- `~/.config/` - User configuration (safe to edit)
- `~/.config/inferna/themes/<custom-name>/` - Custom themes
- `~/.config/inferna/hooks/` - Custom automation hooks

If the request is to develop Inferna itself, this skill is out of scope. Follow repository development instructions instead of this skill.

## Privilege Escalation

For an interactive script or command run in a visible terminal, use `sudo` for
privileged work. Inferna may grant passwordless `sudo` access to particular
commands, and the terminal is the appropriate place to request a password
when one is needed.

Use `pkexec` only when the caller cannot interact with a terminal or cannot
enter a password there, such as a command launched by an agent or a graphical
background process. Do not replace `sudo` with `pkexec` merely because a
command changes system state.

## System Architecture

Inferna is built on:

| Component | Purpose | Config Location |
|-----------|---------|-----------------|
| **Arch Linux** | Base OS | `/etc/`, `~/.config/` |
| **Hyprland** | Wayland compositor/WM | `~/.config/hypr/` |
| **Inferna shell** | Status bar + notifications (Quickshell) | `~/.config/inferna/shell.json` |
| **Launcher/menus** | Quickshell menu | `~/.config/inferna/extensions/inferna-menu.jsonc` |
| **Alacritty/Foot/Kitty/Ghostty** | Terminals | `~/.config/<terminal>/` |
| **Inferna OSD** | On-screen display | Quickshell plugin |

## Command Discovery

Inferna ships a single `omarchy` CLI that dispatches to all `inferna-*` binaries via `omarchy <group> <action>`. Always prefer this form — it is self-documenting and stable. The underlying `inferna-*` binaries still exist on `PATH` and remain safe to read for source.

```bash
# List every documented command and its summary (--all includes hidden commands)
omarchy commands

# Show the commands inside a group
inferna theme --help
omarchy refresh --help
omarchy restart --help

# Show help for a specific command (does not execute it)
inferna theme set --help

# Machine-readable listing (binary, route, summary, args, aliases)
omarchy commands --json

# Read a command's source to understand it
cat $(which inferna-theme-set)
```

### Command Groups

Run `omarchy --help` for the full list. The most common groups:

| Group | Purpose | Example |
|-------|---------|---------|
| `omarchy refresh` | Reset config to defaults (backs up first) | `omarchy refresh shell` |
| `omarchy restart` | Restart a service/app | `omarchy restart shell` |
| `inferna toggle` | Toggle feature on/off | `inferna toggle nightlight` |
| `inferna theme` | Theme management | `inferna theme set <name>` |
| `inferna bar` | Bar layout and widgets | `inferna bar move omarchy.clock --section right` |
| `inferna plugin` | Manage/clone shell plugins | `inferna plugin clone omarchy.clock` |
| `omarchy hook` | Install automation hooks | `omarchy hook install theme-set <script>` |
| `omarchy install` | Install optional software / packages | `omarchy install docker dbs` |
| `omarchy launch` | Launch apps | `omarchy launch browser` |
| `inferna capture` | Screenshots and recordings | `inferna capture screenshot` |
| `omarchy reminder` | Desktop notification reminders | `omarchy reminder 15 "Pickup Jack"` |
| `inferna pkg` | Package management | `inferna pkg add <pkg>` |
| `omarchy setup` | Interactive setup wizards | `omarchy setup security fingerprint` |
| `inferna update` | System updates | `inferna update` |

## Configuration Locations

Hyprland config lives in `~/.config/hypr/` — see [`hyprland.md`](hyprland.md).
The Inferna shell (bar, notifications, plugins, idle) is configured in
`~/.config/inferna/shell.json` — see [`plugins.md`](plugins.md).

### Terminals

```
~/.config/alacritty/alacritty.toml
~/.config/foot/foot.ini
~/.config/kitty/kitty.conf
~/.config/ghostty/config
```

**Command:** `omarchy restart terminal`

### Other Configs

| App | Location |
|-----|----------|
| btop | `~/.config/btop/btop.conf` |
| fastfetch | `/etc/fastfetch/config.jsonc` default; `~/.config/fastfetch/config.jsonc` user override |
| lazygit | `~/.config/lazygit/config.yml` |
| starship | `~/.config/starship.toml` |
| git | `~/.config/git/config` |

## Safe Customization Patterns

### Edit User Config Directly

For simple changes, edit files in `~/.config/`:

```bash
# 1. Read current config
cat ~/.config/hypr/bindings.lua

# 2. Backup before changes
cp ~/.config/hypr/bindings.lua ~/.config/hypr/bindings.lua.bak.$(date +%s)

# 3. Make changes with Edit tool

# 4. Apply changes
# - Hyprland: auto-reloads on save, but MUST validate with `hyprctl reload` and `hyprctl configerrors`
# - Inferna shell: shell.json and user plugin code under ~/.config/inferna/plugins/ hot-reload on save
# - Menus/launcher: ~/.config/inferna/extensions/inferna-menu.jsonc hot-reloads on save
# - Terminals: apply with `omarchy restart terminal` (reloads running terminals; foot picks changes up in new windows)
```

### Reset to Defaults -- ALWAYS SEEK USER CONFIRMATION BEFORE RUNNING

When customizations go wrong:

```bash
# Reset specific config (creates backup automatically)
omarchy refresh shell
omarchy refresh hyprland

# The refresh command:
# 1. Backs up current config with timestamp
# 2. Copies default from $OMARCHY_PATH/config/
# 3. Restarts the component where the refresh needs it (e.g. `refresh shell`)
```

## System Commands

```bash
inferna update                  # Full system update
inferna version                 # Show Inferna version
omarchy debug --no-sudo --print # Debug info (ALWAYS use these flags)
inferna system lock             # Lock screen
inferna system shutdown         # Shutdown
inferna system reboot           # Reboot
```

**IMPORTANT:** Always run `omarchy debug` with `--no-sudo --print` flags to avoid interactive sudo prompts that will hang the terminal.

## Troubleshooting

```bash
# Get debug information (ALWAYS use these flags to avoid interactive prompts)
omarchy debug --no-sudo --print

# Reset specific config to defaults
omarchy refresh <app>

# Refresh specific config file
# config-file path is relative to ~/.config/
# eg. `omarchy refresh config hypr/hyprland.lua` will refresh ~/.config/hypr/hyprland.lua
omarchy refresh config <config-file>

# Full reinstall of configs (nuclear option)
omarchy reinstall
```

## Decision Framework

When user requests system changes:

1. **Is it a stock omarchy command?** Use it directly
2. **Is it a config edit?** Edit in `~/.config/`, never `/usr/share/omarchy/`
3. **Is it a theme customization?** Follow [`theming.md`](theming.md); create a NEW custom theme directory
4. **Is it automation?** Follow [`hooks.md`](hooks.md); use `omarchy hook install` and the hook `.d` directories
5. **Is it a package install?** Use `inferna pkg add <pkgs...>` (or `inferna pkg aur add <pkgs...>` for AUR-only packages)
6. **Is it built-in shell/plugin code?** Follow [`plugins.md`](plugins.md); clone it with `inferna plugin clone`, never edit the packaged copy
7. **Unsure if command exists?** Run `omarchy commands` (or `omarchy <group> --help` for one group)

### Reminder Requests

When the user asks to set a reminder, use `omarchy reminder <minutes> [message]` directly. Convert natural language durations to minutes and title-case short reminder labels when appropriate.

```bash
omarchy reminder 15 "Pickup Jack"
omarchy reminder 60 "Check laundry"
omarchy reminder show
omarchy reminder clear
```

## Out of Scope

This skill intentionally does not cover Inferna source development. Do not use this skill for:
- Editing files in `/usr/share/omarchy/` (`bin/`, `config/`, `default/`, `shell/`, `themes/`, `migrations/`, etc.)
- Creating or editing migrations
- Running `omarchy dev ...` commands

## Example Requests

- "Change my theme to catppuccin" -> `inferna theme set catppuccin`
- "Add a keybinding for Super+E to open file manager" -> Check existing bindings first, then use `o.rebind` to replace one or `o.bind` to add one in `~/.config/hypr/bindings.lua`
- "Configure my external monitor" -> `omarchy hyprland monitor scaling|resolution --monitor <name> ...` for scale and resolution; edit `~/.config/hypr/monitors.lua` only for rotation and the other extras in hyprland.md
- "Make the window gaps smaller" -> Edit `~/.config/hypr/looknfeel.lua`
- "Turn on night light" -> `inferna toggle nightlight` (for time-based schedules, edit `~/.config/hypr/hyprsunset.conf` profiles, then `omarchy restart hyprsunset`)
- "Set a reminder to pickup jack in 15 minutes" -> `omarchy reminder 15 "Pickup Jack"`
- "Show my reminders" -> `omarchy reminder show`
- "Clear all reminders" -> `omarchy reminder clear`
- "Customize the catppuccin theme colors" -> Overlay: put an edited `colors.toml` in `~/.config/inferna/themes/catppuccin/`, then re-apply the theme (see `theming.md`)
- "Run a script every time I change themes" -> Install it with `omarchy hook install theme-set <script>`
- "Change how workspace labels are rendered" -> Clone `omarchy.workspaces`, which switches the bar to `<username>.workspaces`, then edit the clone
- "Lock after ten minutes" -> Set `idle.lock` to `600` in `~/.config/inferna/shell.json`
- "Reset shell/bar to defaults" -> `omarchy refresh shell`
- "Record my screen" -> `omarchy screenrecord --fullscreen`, then `omarchy screenrecord --stop-recording` (see `capture.md`)
- "Report this bug to Inferna" -> Gather diagnostics and a capture of the problem, then file it (see `contributing.md`)
