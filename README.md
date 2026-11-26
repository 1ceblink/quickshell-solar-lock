# Quickshell Solar Lock

An animated, interactive solar-system lockscreen for Wayland, built with [Quickshell](https://quickshell.org)
and Qt Quick 3D. Textured planets orbit a glowing Sun behind a clock, and you unlock by typing your password
(checked through PAM).

- 3D planets with real surface textures, Earth clouds and Moon, Saturn's rings, an asteroid belt and sharp dashed orbits
- Hover a planet or the Sun for a small card with a short description
- Scroll to zoom; the scene fades in on lock and out on unlock
- Clock and date, plus a password pill that shows dots as you type
- Falls back to `hyprlock` if the lock fails to start or crashes

> **Use at your own risk.** This is a hobby lockscreen, not a security-audited one. Read the
> [Safety](#safety-and-recovery) section and test it with a spare TTY logged in before relying on it.

## Requirements

| What | Why |
| --- | --- |
| A Wayland compositor with `ext-session-lock-v1` | Hyprland is what this was built and tested on; Sway and others support the protocol too |
| [`quickshell`](https://archlinux.org/packages/extra/x86_64/quickshell/) | Runs the lock |
| `qt6-quick3d` | The 3D scene |
| `hyprlock` | Provides `/etc/pam.d/hyprlock` for the password check, and is the crash fallback |
| `python` + `python-pillow` | `tools/fetch_textures.py` |
| Optional: the *Scenesa* font | Used for the clock; Qt falls back to a default font if it is missing |

On Arch:

```sh
sudo pacman -S quickshell qt6-quick3d hyprlock python-pillow
```

Quickshell must be built against the Qt version you have installed. If it prints
*"built against Qt X but the system has updated to Qt Y"*, update or rebuild the `quickshell` package;
a mismatch can crash the lock.

## Install

```sh
git clone https://github.com/1ceblink/quickshell-solar-lock.git ~/.local/share/quickshell-solar-lock
cd ~/.local/share/quickshell-solar-lock

# download planet textures (CC BY 4.0, see Credits) and build the ring and bump maps
python3 tools/fetch_textures.py
```

> **The texture step is required.** The planet textures are not stored in this repository (they are CC BY 4.0
> and are downloaded instead). Without running `tools/fetch_textures.py` the planets render as untextured
> blobs, and `bin/lock-solar` will refuse to start the scene and use `hyprlock` instead. The script needs
> an internet connection, about 7 MB of disk, and `python-pillow`.

### Preview without locking

```sh
qs -p ~/.local/share/quickshell-solar-lock/dev.qml
```

This opens the scene in a normal window. Nothing is locked, and typing only logs to the terminal.

### Hook it up to a key

`bin/lock-solar` starts the lock and falls back to `hyprlock` if it fails. Point your lock key at it
and allow Hyprland to restore the lock after a crash.

`hyprland.conf`:

```ini
misc {
    allow_session_lock_restore = true
}
bind = SUPER, L, exec, ~/.local/share/quickshell-solar-lock/bin/lock-solar
```

`hyprland.lua`:

```lua
-- inside hl.config({ ... })
misc = { allow_session_lock_restore = true },

hl.bind("SUPER + L", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/share/quickshell-solar-lock/bin/lock-solar"))
```

The same script works for an idle daemon (for example `lock_cmd` in `hypridle.conf`).

## Using it

| Action | Result |
| --- | --- |
| Hover a planet or the Sun | Ring and description card |
| Scroll | Zoom in or out |
| Type | Dots appear in the pill (the password is never shown) |
| Backspace / Esc | Delete a character / clear all |
| Enter | Submit; a wrong password shows "wrong password" |

## Customising

Everything is in `Scene.qml`:

- `planets` (top of the file): names, orbit radius, size, tilt, spin speed and the description text
- `homeZ`: camera distance; increase it to shrink the whole system on screen
- `fadeIn` / `fadeOut`: fade durations
- the clock block: font (`Scenesa`), size and position
- `shell.qml`: `config: "hyprlock"` is the PAM service name; use `"login"` if you do not use `hyprlock`

The textures live in `textures/` and are not part of the repo (see below). If a planet renders without
a surface, run `tools/fetch_textures.py` again.

## Safety and recovery

- **Keep a TTY open** the first time: press `Ctrl+Alt+F3`, log in, then return with your session's TTY key
  (usually `Ctrl+Alt+F1` or `F2`). From there `pkill qs` stops a stuck lock.
- If the lock program crashes, Hyprland keeps the session locked (a red screen). With
  `allow_session_lock_restore` on, `lock-solar` starts `hyprlock` so you can unlock normally.
- `shell.qml` disables Quickshell's file watching on purpose. Hot-reloading a running lock destroys the
  lock object and leaves a stuck process that makes the key do nothing. If `Super+L` ever does nothing,
  run `pkill qs` and try again.
- Do not run the lock from a folder you are actively editing while testing; use `dev.qml` for that.

## Credits

- Planet, Sun, Moon and ring textures: [Solar System Scope](https://www.solarsystemscope.com/textures/),
  licensed [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). They are downloaded by
  `tools/fetch_textures.py` and are not redistributed here. Please credit them if you share screenshots or videos.
- [Quickshell](https://quickshell.org) and [Qt](https://www.qt.io).
