#!/bin/sh
# Undo install.sh: restore the Hyprland lock bind, remove the KDE override and delete the code and textures.
#
#   ./uninstall.sh                    from a checkout or from the default install
#   curl -fsSL <raw url>/uninstall.sh | sh      works on the default install (~/.local/share/quickshell-solar-lock)
#
# Options (pass after `sh -s --` when piping):
#   --packages   also offer to remove the pacman packages install.sh added (only those, after asking)
#   --yes        do not ask before each step
#
# Dependencies you already had are never removed.
set -eu

main() {
    DEST="${SOLAR_LOCK_DIR:-$HOME/.local/share/quickshell-solar-lock}"
    STATE="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-solar-lock"
    PKGS=0 ASK=1
    for a in "$@"; do
        case "$a" in
            --packages) PKGS=1 ;;
            --yes|-y) ASK=0 ;;
            -h|--help) sed -n '2,12p' "$0" 2>/dev/null; return 0 ;;
            *) echo "uninstall.sh: unknown option $a" >&2; return 2 ;;
        esac
    done

    say() { printf '\n==> %s\n' "$*"; }
    confirm() {   # confirm "question": reads from the terminal, because stdin is the script when piped
        [ "$ASK" = 1 ] || return 0
        printf '%s [Y/n] ' "$1"
        read -r ans </dev/tty || return 1
        case "$ans" in n|N) return 1 ;; esac
    }

    # the checkout this script lives in, else the default install
    HERE=; [ -f "$0" ] && HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)   # piped from curl: $0 is just "sh"
    if [ -n "$HERE" ] && [ -f "$HERE/shell.qml" ] && [ -f "$HERE/tools/patch_hypr_bind.py" ]; then
        DIR=$HERE
    else
        DIR=$DEST
    fi
    if [ ! -f "$DIR/tools/patch_hypr_bind.py" ]; then
        echo "uninstall.sh: no install found at $DIR (set SOLAR_LOCK_DIR if it is elsewhere)" >&2
        return 1
    fi

    # the installed copy may predate --revert: bring a git clone up to date first
    if ! grep -q -- "--revert" "$DIR/tools/patch_hypr_bind.py" && [ -d "$DIR/.git" ]; then
        git -C "$DIR" pull --ff-only -q || true
    fi
    grep -q -- "--revert" "$DIR/tools/patch_hypr_bind.py" || {
        echo "uninstall.sh: $DIR is too old to undo the Hyprland change; update it (git pull) and run again" >&2
        return 1
    }

    # 1. Hyprland: put the old lock bind back
    say "Hyprland config"
    if python3 -I "$DIR/tools/patch_hypr_bind.py" "$DIR/bin/lock-solar" --revert --check; then
        if confirm "Apply these changes?"; then
            python3 -I "$DIR/tools/patch_hypr_bind.py" "$DIR/bin/lock-solar" --revert >/dev/null
        fi
    fi

    # 2. KDE Plasma override
    if [ -f "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/shells/org.kde.plasma.desktop/.solar-lock-override" ]; then
        say "KDE Plasma lockscreen"
        confirm "Remove the KDE lockscreen override?" && "$DIR/bin/uninstall-kde"
    fi

    # 3. packages install.sh added
    if [ "$PKGS" = 1 ]; then
        say "Packages"
        if [ -s "$STATE/packages" ]; then
            LIST=$(sort -u "$STATE/packages" | tr '\n' ' ')
            echo "install.sh added: $LIST"
            if confirm "Remove them with sudo pacman -Rs?"; then
                sudo pacman -Rs $LIST </dev/tty && rm -f "$STATE/packages"
            fi
        else
            echo "install.sh did not add any packages (or they were recorded by an older version)."
        fi
    fi

    # 4. the code, textures and generated meshes. Only the default install is deleted: a checkout you
    #    cloned elsewhere is yours to remove.
    say "Code and textures"
    if [ "$DIR" = "$DEST" ]; then
        if confirm "Delete $DIR (about $(du -sh "$DIR" | cut -f1))?"; then
            rm -rf "$DIR"
            rmdir "$STATE" 2>/dev/null || true
            echo "removed $DIR"
        fi
    else
        echo "$DIR is not the default install location, so it is left in place; delete it yourself if you want."
    fi

    say "Done"
    echo "If you bound your lock key to ~/.local/bin/lock-solar or another copy yourself, that is not touched."
}

main "$@"
exit
