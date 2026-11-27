#!/usr/bin/env python3
"""Point the Hyprland lock key at bin/lock-solar.

Looks for ~/.config/hypr/hyprland.lua and hyprland.conf. In each file it
  - rewrites an existing SUPER+L exec bind whose command looks like a lock command (hyprlock, loginctl
    lock-session, lock-solar, ...) to run bin/lock-solar,
  - adds the bind if the file has no L bind at all,
  - leaves an L bind that runs something else alone and says so,
  - turns misc:allow_session_lock_restore on (adds it to the misc block in hyprland.conf; in Lua it only
    flips an existing value).
The original file is copied to <name>.bak-solar (or .bak-solar-<n>) before anything is written.

  patch_hypr_bind.py <path to lock-solar> [--check]     --check only prints what would change
  patch_hypr_bind.py <path to lock-solar> --revert      undo it (what uninstall.sh runs); honours --check too

--revert restores the newest .bak-solar copy when the file is still exactly what this script made from it. If you have
edited the file since, it only puts the old lock command back (or removes the bind it added) and keeps your edits.
"""
import glob
import os
import re
import sys

LOCKISH = re.compile(r"lock-solar|solar-lock|hyprlock|lock-session|loginctl|swaylock|gtklock|waylock|quickshell|\bqs\b")


def home_rel(path):
    home = os.path.expanduser("~")
    return path[len(home) + 1:] if path.startswith(home + "/") else None


def conf_cmd(path):
    rel = home_rel(path)
    return "~/" + rel if rel else path


def lua_cmd(path):
    rel = home_rel(path)
    return 'os.getenv("HOME") .. "/%s"' % rel if rel else '"%s"' % path


def patch_conf(text, target):
    notes, cmd = [], conf_cmd(target)
    lines = text.split("\n")
    found = False
    for i, line in enumerate(lines):
        m = re.match(r"^(\s*bind[a-z]*\s*=\s*)([^,]*),\s*([lL])\s*,\s*exec\s*,\s*(.*?)\s*$", line)
        if not m:
            continue
        found = True
        if m.group(4) in (cmd, target):
            notes.append("lock bind already points at lock-solar (line %d)" % (i + 1))
        elif LOCKISH.search(m.group(4)):
            lines[i] = "%s%s, %s, exec, %s" % (m.group(1), m.group(2), m.group(3), cmd)
            notes.append("line %d: '%s' -> '%s'" % (i + 1, m.group(4), cmd))
        else:
            notes.append("line %d binds L to '%s': left alone, bind your lock key to %s yourself" % (i + 1, m.group(4), cmd))
        break
    if not found:
        if any(re.match(r"^\s*bind[a-z]*\s*=\s*[^,]*,\s*[lL]\s*,", l) for l in lines):
            notes.append("L is bound to something other than exec: left alone, bind your lock key to %s yourself" % cmd)
        else:
            if lines and lines[-1] == "":
                lines.pop()
            lines += ["", "bind = SUPER, L, exec, " + cmd, ""]
            notes.append("added: bind = SUPER, L, exec, " + cmd)
    for i, line in enumerate(lines):
        m = re.match(r"^(\s*allow_session_lock_restore\s*=\s*)(\S+)(.*)$", line)
        if m:
            if m.group(2).lower() not in ("true", "1", "yes", "on"):
                lines[i] = m.group(1) + "true" + m.group(3)
                notes.append("line %d: allow_session_lock_restore -> true" % (i + 1))
            break
    else:
        for i, line in enumerate(lines):
            if re.match(r"^\s*misc\s*\{", line):
                lines.insert(i + 1, "    allow_session_lock_restore = true")
                break
        else:
            lines += ["misc {", "    allow_session_lock_restore = true", "}", ""]
        notes.append("added misc:allow_session_lock_restore = true")
    return "\n".join(lines), notes


def call_end(s, start):
    """Index just past the ')' that closes the '(' at s[start]."""
    depth, quote = 0, None
    for j in range(start, len(s)):
        c = s[j]
        if quote:
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return j + 1
    return None


def patch_lua(text, target):
    notes, cmd = [], lua_cmd(target)
    lines = text.split("\n")
    found = False
    for i, line in enumerate(lines):
        if not re.match(r"^\s*hl\.bind\(", line) or not re.search(r'[+\s"]L"\s*,', line) or "exec_cmd(" not in line:
            continue
        found = True
        a = line.index("exec_cmd(") + len("exec_cmd")
        b = call_end(line, a)
        if b is None:
            notes.append("line %d: could not parse, left alone" % (i + 1))
            break
        old = line[a + 1:b - 1].strip()
        if old.replace(" ", "") == cmd.replace(" ", "") or old.strip('"') == target:
            notes.append("lock bind already points at lock-solar (line %d)" % (i + 1))
        elif LOCKISH.search(old):
            lines[i] = line[:a + 1] + cmd + line[b - 1:]
            notes.append("line %d: %s -> %s" % (i + 1, old, cmd))
        else:
            notes.append("line %d binds L to %s: left alone, bind your lock key to %s yourself" % (i + 1, old, target))
        break
    if not found:
        if any(re.match(r"^\s*hl\.bind\(", l) and re.search(r'[+\s"]L"\s*,', l) for l in lines):
            notes.append("L is bound to something other than exec_cmd: left alone, bind your lock key to %s yourself" % target)
        else:
            if lines and lines[-1] == "":
                lines.pop()
            lines += ["", 'hl.bind("SUPER + L", hl.dsp.exec_cmd(%s))' % cmd, ""]
            notes.append("added: hl.bind(\"SUPER + L\", hl.dsp.exec_cmd(%s))" % cmd)
    new = []
    for line in lines:
        m = re.match(r"^(\s*allow_session_lock_restore\s*=\s*)(\w+)(.*)$", line)
        if m and m.group(2) != "true":
            line = m.group(1) + "true" + m.group(3)
            notes.append("allow_session_lock_restore -> true")
        new.append(line)
    text = "\n".join(new)
    if "allow_session_lock_restore" not in text:
        notes.append("add `allow_session_lock_restore = true` to the misc table of hl.config yourself")
    return text, notes


def find_conf_l(lines):
    for i, line in enumerate(lines):
        m = re.match(r"^(\s*bind[a-z]*\s*=\s*)([^,]*),\s*([lL])\s*,\s*exec\s*,\s*(.*?)\s*$", line)
        if m:
            return i, m
    return None, None


def find_lua_l(lines):
    for i, line in enumerate(lines):
        if re.match(r"^\s*hl\.bind\(", line) and re.search(r'[+\s"]L"\s*,', line) and "exec_cmd(" in line:
            a = line.index("exec_cmd(") + len("exec_cmd")
            b = call_end(line, a)
            if b is not None:
                return i, a, b, line[a + 1:b - 1].strip()
    return None, 0, 0, None


def revert_conf(cur, bak, target):
    if patch_conf(bak, target)[0] == cur:
        return bak, ["restored the original file"]
    cmd, lines = conf_cmd(target), cur.split("\n")
    i, m = find_conf_l(lines)
    if m is None or m.group(4) not in (cmd, target):
        return cur, ["no lock-solar bind found, nothing to undo"]
    _, old = find_conf_l(bak.split("\n"))
    if old:
        lines[i] = "%s%s, %s, exec, %s" % (m.group(1), m.group(2), m.group(3), old.group(4))
        return "\n".join(lines), ["line %d: back to '%s'" % (i + 1, old.group(4))]
    del lines[i]
    return "\n".join(lines), ["line %d: removed the bind this script added" % (i + 1)]


def revert_lua(cur, bak, target):
    if patch_lua(bak, target)[0] == cur:
        return bak, ["restored the original file"]
    cmd, lines = lua_cmd(target), cur.split("\n")
    i, a, b, now = find_lua_l(lines)
    if now is None or not (now.replace(" ", "") == cmd.replace(" ", "") or now.strip('"') == target):
        return cur, ["no lock-solar bind found, nothing to undo"]
    j, oa, ob, old = find_lua_l(bak.split("\n"))
    if old is not None:
        lines[i] = lines[i][:a + 1] + old + lines[i][b - 1:]
        return "\n".join(lines), ["line %d: back to %s" % (i + 1, old)]
    del lines[i]
    return "\n".join(lines), ["line %d: removed the bind this script added" % (i + 1)]


def backup(path):
    dest, n = path + ".bak-solar", 1
    while os.path.exists(dest):
        n += 1
        dest = "%s.bak-solar-%d" % (path, n)
    with open(path, "rb") as src, open(dest, "wb") as out:
        out.write(src.read())
    return dest


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check, revert = "--check" in sys.argv, "--revert" in sys.argv
    if len(args) != 1:
        sys.exit(__doc__)
    target = os.path.abspath(args[0])
    base = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "hypr")
    found = False
    for name, patch, undo in (("hyprland.lua", patch_lua, revert_lua), ("hyprland.conf", patch_conf, revert_conf)):
        path = os.path.join(base, name)
        if not os.path.isfile(path):
            continue
        found = True
        with open(path) as f:
            old = f.read()
        if revert:
            baks = sorted(glob.glob(glob.escape(path) + ".bak-solar*"), key=os.path.getmtime)   # newest = made by the last patch
            bak = baks[-1] if baks else ""
            if not bak:
                print(path)
                print("  no .bak-solar copy: nothing to undo")
                continue
            with open(bak) as f:
                new, notes = undo(old, f.read(), target)
        else:
            new, notes = patch(old, target)
        print(path)
        for n in notes:
            print("  " + n)
        if new != old and not check:
            if not revert:
                print("  backup: " + backup(path))
            with open(path, "w") as f:
                f.write(new)
            if revert and notes == ["restored the original file"]:
                os.remove(bak)
    if not found:
        print("no Hyprland config found in %s" % base)
    sys.exit(0 if found else 3)


if __name__ == "__main__":
    main()
