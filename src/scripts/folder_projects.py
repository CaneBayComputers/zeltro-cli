#!/usr/bin/env python3
"""Registry for folder projects: a folder plus an AI session, with no containers.

One JSON record per project in <projects_dir>/.zeltro/folders/<name>.json:

    {"kind": "folder", "origin": "created" | "added", "path": "/real/path",
     "created_at": "...", "metadata": {"emoji", "name", "description", "idea", "last_on"}}

- created: `zeltro new folder`. <projects_dir>/<name> is a real directory.
- added:   `zeltro add <path>`. <projects_dir>/<name> is a symlink to a folder
           that lives anywhere on this host. Nothing is written inside it.

The record is what makes a project a folder project; every other project is a
Docker one. Metadata lives here rather than in the folder so an added folder is
never touched, and so both origins work the same way.

Usage: folder_projects.py <command> <projects_dir> [args...]
"""
import json
import os
import sys
import time


def reg_dir(pdir):
    return os.path.join(pdir, ".zeltro", "folders")


def rec_path(pdir, name):
    return os.path.join(reg_dir(pdir), name + ".json")


def load(pdir, name):
    try:
        with open(rec_path(pdir, name), encoding="utf-8") as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) and d.get("kind") == "folder" else None
    except (OSError, ValueError):
        return None


def save(pdir, name, rec):
    os.makedirs(reg_dir(pdir), exist_ok=True)
    tmp = rec_path(pdir, name) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(rec, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, rec_path(pdir, name))


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def meta_out(rec, full):
    out = {}
    for k, v in (rec.get("metadata") or {}).items():
        if k == "idea" and not full:
            out["has_idea"] = bool(v)
            continue
        out["display_name" if k == "name" else k] = v
    return out


def emit(obj):
    try:
        print(json.dumps(obj, ensure_ascii=False))
    except UnicodeEncodeError:
        print(json.dumps(obj))


def main(argv):
    if len(argv) < 3:
        sys.exit("usage: folder_projects.py <command> <projects_dir> [args]")
    cmd, pdir = argv[1], argv[2]
    args = argv[3:]

    if cmd == "kind":
        # folder | docker | none
        name = args[0]
        if load(pdir, name):
            print("folder")
        elif os.path.isdir(os.path.join(pdir, name)):
            print("docker")
        else:
            print("none")
        return 0

    if cmd == "info":
        # {"kind","origin","path","missing"}, or exit 1 if not a folder project
        name = args[0]
        rec = load(pdir, name)
        if not rec:
            return 1
        path = rec.get("path") or os.path.join(pdir, name)
        emit({"kind": "folder", "origin": rec.get("origin", "created"),
              "path": path, "missing": not os.path.isdir(path)})
        return 0

    if cmd == "list":
        # Names of every folder project, one per line (includes missing ones).
        try:
            names = sorted(f[:-5] for f in os.listdir(reg_dir(pdir)) if f.endswith(".json"))
        except OSError:
            names = []
        for n in names:
            if load(pdir, n):
                print(n)
        return 0

    if cmd == "create":
        name, origin, path = args[0], args[1], args[2]
        save(pdir, name, {"kind": "folder", "origin": origin, "path": path,
                          "created_at": now(), "metadata": {}})
        return 0

    if cmd == "forget":
        try:
            os.remove(rec_path(pdir, args[0]))
        except FileNotFoundError:
            pass
        return 0

    if cmd == "rename":
        # rename <old> <new> [path]: move the record, and the path with it for
        # a created folder (an added one stays where the user keeps it).
        old, new = args[0], args[1]
        rec = load(pdir, old)
        if not rec:
            return 1
        if len(args) > 2 and args[2]:
            rec["path"] = args[2]
        save(pdir, new, rec)
        os.remove(rec_path(pdir, old))
        return 0

    if cmd == "find-path":
        # The project name already registered for this real path, if any.
        target = os.path.realpath(args[0])
        try:
            files = sorted(os.listdir(reg_dir(pdir)))
        except OSError:
            files = []
        for f in files:
            if not f.endswith(".json"):
                continue
            rec = load(pdir, f[:-5])
            if rec and rec.get("path") and os.path.realpath(rec["path"]) == target:
                print(f[:-5])
                return 0
        return 1

    if cmd == "meta-get":
        rec = load(pdir, args[0])
        if not rec:
            return 1
        emit(meta_out(rec, len(args) > 1 and args[1] == "full"))
        return 0

    if cmd == "meta-raw":
        # One raw metadata value (e.g. the idea), no trailing newline.
        rec = load(pdir, args[0])
        if not rec:
            return 1
        sys.stdout.write(str((rec.get("metadata") or {}).get(args[1], "")))
        return 0

    if cmd == "meta-set":
        # meta-set <name> <key> <value-file> [delete]
        name, key, vfile = args[0], args[1], args[2]
        rec = load(pdir, name)
        if not rec:
            return 1
        meta = rec.setdefault("metadata", {})
        if len(args) > 3 and args[3] == "delete":
            meta.pop(key, None)
        else:
            with open(vfile, encoding="utf-8", errors="surrogateescape") as fh:
                meta[key] = fh.read()
        save(pdir, name, rec)
        return 0

    if cmd == "touch":
        rec = load(pdir, args[0])
        if not rec:
            return 0
        rec.setdefault("metadata", {})["last_on"] = now()
        save(pdir, args[0], rec)
        return 0

    sys.exit("unknown command: " + cmd)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
