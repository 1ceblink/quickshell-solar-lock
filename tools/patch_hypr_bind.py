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
"""
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
    check = "--check" in sys.argv
    if len(args) != 1:
        sys.exit(__doc__)
    target = os.path.abspath(args[0])
    base = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "hypr")
    changed = found = False
    for name, fn in (("hyprland.lua", patch_lua), ("hyprland.conf", patch_conf)):
        path = os.path.join(base, name)
        if not os.path.isfile(path):
            continue
        found = True
        with open(path) as f:
            old = f.read()
        new, notes = fn(old, target)
        print(path)
        for n in notes:
            print("  " + n)
        if new != old:
            changed = True
            if not check:
                print("  backup: " + backup(path))
                with open(path, "w") as f:
                    f.write(new)
    if not found:
        print("no Hyprland config found in %s" % base)
    sys.exit(0 if found else 3)


if __name__ == "__main__":
    main()
