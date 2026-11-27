#!/bin/sh
# One-step setup for the solar-system lockscreen: dependencies, code, textures and meshes.
#
#   ./install.sh                 from a checkout: install dependencies, download textures, build meshes
#   curl -fsSL <raw url>/install.sh | sh     clones to ~/.local/share/quickshell-solar-lock first
#
# Options (pass after `sh -s --` when piping):
#   --kde        also set up the KDE Plasma lockscreen (bin/install-kde)
#   --no-deps    skip the pacman step (other distros: install the packages from the README yourself)
#   --yes        do not ask before running pacman
#
# It never edits your compositor config: it prints the line to add at the end.
set -eu

REPO=https://github.com/1ceblink/quickshell-solar-lock.git
DEST="${SOLAR_LOCK_DIR:-$HOME/.local/share/quickshell-solar-lock}"
PKGS="quickshell qt6-quick3d assimp hyprlock python-pillow python-numpy"

KDE=0 DEPS=1 ASK=1
for a in "$@"; do
    case "$a" in
        --kde) KDE=1 ;;
        --no-deps) DEPS=0 ;;
        --yes|-y) ASK=0 ;;
        -h|--help) sed -n '2,12p' "$0" 2>/dev/null; exit 0 ;;
        *) echo "install.sh: unknown option $a" >&2; exit 2 ;;
    esac
done

say() { printf '\n==> %s\n' "$*"; }
die() { echo "install.sh: $*" >&2; exit 1; }

# 1. dependencies
if [ "$DEPS" = 1 ]; then
    if command -v pacman >/dev/null 2>&1; then
        MISSING=$(pacman -T $PKGS || true)
        if [ -n "$MISSING" ]; then
            say "Missing packages: $(echo $MISSING | tr '\n' ' ')"
            if [ "$ASK" = 1 ]; then
                printf 'Install them with sudo pacman -S? [Y/n] '
                read -r ans </dev/tty || ans=n
                case "$ans" in n|N) die "dependencies are required, rerun with --no-deps if you installed them yourself" ;; esac
            fi
            # stdin is the script itself when piped from curl: pacman must read its answers from the terminal,
            # or it swallows the rest of the script as its reply and aborts
            sudo pacman -S --needed $MISSING </dev/tty
        else
            say "Dependencies already installed"
        fi
    else
        echo "pacman not found: install the equivalents of: $PKGS (see the README), then rerun with --no-deps" >&2
    fi
fi
command -v python3 >/dev/null 2>&1 || die "python3 is required"

# 2. code: use the checkout this script lives in, otherwise clone or update the default location
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)
if [ -n "$HERE" ] && [ -f "$HERE/shell.qml" ] && [ -f "$HERE/tools/fetch_textures.py" ]; then
    DIR=$HERE
else
    command -v git >/dev/null 2>&1 || die "git is required"
    if [ -d "$DEST/.git" ]; then
        say "Updating $DEST"
        git -C "$DEST" pull --ff-only
    else
        [ -e "$DEST" ] && die "$DEST exists and is not a checkout; move it or set SOLAR_LOCK_DIR"
        say "Cloning to $DEST"
        git clone "$REPO" "$DEST"
    fi
    DIR=$DEST
fi
cd "$DIR"

# 3. textures (checksummed downloads) and generated meshes
say "Downloading textures"
python3 tools/fetch_textures.py
say "Building the Hearthian meshes"
python3 tools/make_hearthian_meshes.py

# 4. optional KDE setup
if [ "$KDE" = 1 ]; then
    say "Setting up the KDE Plasma lockscreen"
    bin/install-kde
fi

say "Done"
cat <<EOF
Preview in a window (nothing is locked):
    qs -p $DIR/dev.qml

Hyprland: bind your lock key to the launcher, and let it restore the lock after a crash.
    hyprland.conf:  misc { allow_session_lock_restore = true }
                    bind = SUPER, L, exec, $DIR/bin/lock-solar
EOF
[ "$KDE" = 1 ] || echo "KDE Plasma: rerun with --kde (or run bin/install-kde)."
