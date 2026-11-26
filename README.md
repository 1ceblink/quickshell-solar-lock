# Solar Lock

An animated, interactive 3D solar system as your lockscreen. Textured planets orbit a glowing Sun behind a
clock; hover a planet to learn about it, click to fly in on it, and type your password to unlock.

![Solar Lock: the orbiting solar system with a clock, then a flight in on Earth and Saturn with their description cards](docs/solar-lock.gif)

- **Real-looking worlds:** photo textures for every planet, Earth's clouds and Moon, Saturn's rings, an asteroid belt and sharp dashed orbits
- **Interactive:** hover a planet, the Moon or the Sun for a description card, click to zoom in, scroll to zoom
- **Supernova:** every 22 minutes of being locked the textured Sun slowly shrinks into a small white sphere, turns blue and swells in a growing glow, then the whole screen blows out white and fades to black before everything fades back in
- **Polished:** fade in on lock, fade out on unlock, clock and date, a password pill with dots
- **Safe fallback:** if the lock fails to start or crashes, `hyprlock` takes over (Hyprland)

| Desktop | How it works | Setup |
| --- | --- | --- |
| **Hyprland**, Sway and other compositors with `ext-session-lock-v1` | [Quickshell](https://quickshell.org) draws the lock and checks the password through PAM | [Hyprland setup](#hyprland-and-other-wayland-compositors) |
| **KDE Plasma** | The same scene runs inside KDE's own screen locker | [KDE Plasma setup](#kde-plasma) |

> **Use at your own risk.** This is a hobby lockscreen, not a security-audited one. Test it with a spare TTY
> logged in before you rely on it (see [Safety and recovery](#safety-and-recovery)).

## Quick start

**1. Install the dependencies** (Arch package names):

```sh
sudo pacman -S quickshell qt6-quick3d hyprlock python-pillow
```

| Package | Used for |
| --- | --- |
| `quickshell` | Runs the lock on Hyprland and similar compositors (not needed on KDE) |
| `qt6-quick3d` | The 3D scene |
| `hyprlock` | Provides the PAM service for the password check, and the crash fallback (not needed on KDE) |
| `python-pillow` | The texture script below |

Optional: the *Scenesa* font for the clock. Qt uses a default font if it is missing.

Quickshell must be built against the Qt version you have installed. If it warns *"built against Qt X but the
system has updated to Qt Y"*, update or rebuild the `quickshell` package, because a mismatch can crash the lock.

**2. Get the code and download the textures:**

```sh
git clone https://github.com/1ceblink/quickshell-solar-lock.git ~/.local/share/quickshell-solar-lock
cd ~/.local/share/quickshell-solar-lock
python3 tools/fetch_textures.py
```

> **The texture step is required.** The planet textures are not stored in this repository (they are CC BY 4.0,
> so they are downloaded instead). Without them the planets render as untextured blobs, and `bin/lock-solar`
> refuses to start the scene and uses `hyprlock` instead. The script needs an internet connection and about
> 7 MB of disk.

**3. Preview it in a window** (Hyprland route; on KDE use the test command in the [KDE section](#kde-plasma)). Nothing is locked, and typing only prints to the terminal:

```sh
qs -p ~/.local/share/quickshell-solar-lock/dev.qml
```

Then continue with the setup for your desktop.

## Hyprland and other Wayland compositors

`bin/lock-solar` starts the lock and falls back to `hyprlock` if it fails. Point your lock key at it, and let
Hyprland restore the lock after a crash.

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

The same script works as the lock command of an idle daemon (for example `lock_cmd` in `hypridle.conf`).
On other compositors that support `ext-session-lock-v1`, bind your lock key to the same script.

## KDE Plasma

KWin does not implement `ext-session-lock-v1`, so `bin/lock-solar` cannot lock a Plasma session. Instead the
same `Scene.qml` runs inside KDE's screen locker (`kscreenlocker_greet`), which keeps doing the real locking,
the password check, multi-monitor handling and crash recovery. Quickshell and `hyprlock` are not needed.

```sh
python3 tools/fetch_textures.py      # if you have not done it yet
bin/install-kde
```

Test it in a window without locking, then lock with `Meta+L` (keep a TTY logged in the first time):

```sh
/usr/lib/kscreenlocker_greet --testing
```

To undo it, run `bin/uninstall-kde` and log out and back in.

**What `install-kde` does.** The locker loads its UI from `lockscreen/LockScreen.qml` in the Plasma shell
package `org.kde.plasma.desktop`. Plasma only serves files inside a package, and a user package with that name
hides the system one completely, so the script:

- copies `/usr/share/plasma/shells/org.kde.plasma.desktop` to `~/.local/share/plasma/shells/` and replaces only
  `contents/lockscreen/` with `kde/lockscreen/LockScreen.qml` plus symlinks to `Scene.qml` and `textures/`.
  Everything else is identical, so the desktop, panels and widgets are unaffected;
- installs `~/.config/plasma-workspace/env/solar-lock-kde.sh`, which rebuilds that copy from the current system
  package at every login, so a Plasma update never leaves a stale copy behind.

Because `Scene.qml` and `textures/` are symlinks, updating this repository updates the KDE lock too. Only a
change to `kde/lockscreen/LockScreen.qml` needs `bin/install-kde` again (or a re-login).

Compared with the stock Plasma lockscreen you lose the Sleep / Switch User buttons, media controls, the
keyboard-layout switcher and the authenticator picker. If the QML ever fails to load, KDE shows its built-in
fallback lockscreen and the session stays locked.

## Using it

| Action | Result |
| --- | --- |
| Hover a planet, the Moon or the Sun | The body glows softly in its own colour and a card shows its name, orbit and a short description |
| Click a planet, the Moon or the Sun | The camera glides in on it, and its description card appears once the zoom has finished; click it again, or empty space, to zoom back out |
| Scroll | Zoom in or out |
| Type | Dots appear in the pill (the password itself is never shown) |
| Backspace / Ctrl+Backspace | Delete one character / clear everything |
| Esc | Zoom back out when zoomed in on a planet, otherwise clear the password |
| Enter | Submit. A wrong password shows "wrong password" in red; typing again clears it |

## The supernova

![The Sun shrinks into a small white sphere, turns blue and swells, then the screen blows out white and fades to black before everything fades back in](docs/supernova.gif)

Every **22 minutes of being locked** the Sun goes supernova.

The timer counts time spent locked and starts over every time you lock, so a short lock never sees it. Unlocking while it plays cancels it. Change the interval with `novaInterval` in `Scene.qml` (milliseconds, default `22 * 60 * 1000`).

## Customising

Almost everything is in `Scene.qml`:

| What | Where |
| --- | --- |
| Planet names, orbit radius, size, tilt, spin speed and description text | the `planets` list at the top |
| How far the camera sits (increase it to shrink the whole system) | `homeZ` |
| Fade durations | `fadeIn` and `fadeOut` |
| How often the supernova happens (milliseconds, default `22 * 60 * 1000`; it counts time spent locked and starts over each time you lock) | `novaInterval` |
| The supernova's timing, size and colours | the `// ---- supernova` block and the `novaAnim` sequence |
| Clock font, size and position | the `// clock` block |
| Lighting and anti-aliasing | the `PointLight` and `SceneEnvironment` in the 3D view |

Two settings live in `shell.qml`: `config: "hyprlock"` is the PAM service name (use `"login"` if you do not
have `hyprlock`), and `settings.watchFiles: false` must stay off (see below).

While you experiment, use `dev.qml` rather than the real lock.

## Safety and recovery

- **Keep a TTY open the first time.** Press `Ctrl+Alt+F3`, log in, then return with your session's TTY key
  (usually `Ctrl+Alt+F1` or `F2`). From the TTY, `pkill qs` stops a stuck lock.
- **If the lock crashes**, Hyprland keeps the session locked and shows a red screen. With
  `allow_session_lock_restore` on, `lock-solar` starts `hyprlock` so you can unlock normally.
- **Memory:** the lock uses roughly 240 MB while it is running (most of it texture memory) and exits completely
  after you unlock.

### Troubleshooting

| Problem | Fix |
| --- | --- |
| The lock key does nothing | A stuck lock process is blocking it. Run `pkill qs` and try again. Quickshell hot-reloads when files in its folder change and a reload destroys a running lock, which is why `shell.qml` turns file watching off |
| Planets look flat and untextured, or you get `hyprlock` instead | Run `python3 tools/fetch_textures.py` |
| Warning about a Qt version mismatch | Update or rebuild the `quickshell` package |
| The password is always rejected | Check the PAM service name in `shell.qml` (see Customising) |
| The clock uses a plain font | Install the Scenesa font, or set another `font.family` in the clock block |

## Repository layout

```text
LICENSE                         MIT
shell.qml                       the real lock (Hyprland and other compositors)
Scene.qml                       the 3D scene, clock, password pill and all interaction (shared by every desktop)
dev.qml                         windowed preview, no locking
bin/lock-solar                  launcher with the hyprlock fallback
bin/preview                     opens the scene in a window, nothing is locked
bin/install-kde, uninstall-kde  KDE Plasma setup and removal
kde/lockscreen/LockScreen.qml   the KDE greeter UI that hosts Scene.qml
tools/fetch_textures.py         downloads the textures and builds the ring and bump maps
textures/                       created by the script, not committed
```

## Credits and licence

- Planet, Sun, Moon and ring textures: [Solar System Scope](https://www.solarsystemscope.com/textures/),
  licensed [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). They are downloaded by
  `tools/fetch_textures.py` and are not redistributed here. Please credit them if you share screenshots or videos.
- Built with [Quickshell](https://quickshell.org) and [Qt](https://www.qt.io).
- Licence: [MIT](LICENSE), except `kde/lockscreen/LockScreen.qml`, which keeps its `GPL-2.0-or-later` header because it follows KDE's own lockscreen. The planet textures are not part of this repository; they are CC BY 4.0 (see above).
