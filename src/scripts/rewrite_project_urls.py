#!/usr/bin/env python3
"""Point an installed app's own base URL at the address the project really has.

Usage: rewrite_project_urls.py <project_dir> <ip> <project_name> [app_slug] [--top-level-only]

Installers write an app's own URL as http://<name> -- APP_URL, ROOT_URL,
NEXTAUTH_URL and friends, into docker-compose.yaml, .env files and config files.
That host resolves nowhere on the host now that Zeltro no longer writes
/etc/hosts, and an app configured with it redirects the browser to it (Ghost,
Grafana, Gitea) or refuses every other Host (FreeScout's 403 "Untrusted Host").

Rewrites, in every text file of the project directory:

  http://<name>, https://, ws://, wss://  ->  the same scheme and <ip>
  __ZELTRO_IP__                           ->  <ip>
  __ZELTRO_PROJECT__                      ->  <project_name>

<name> is the project name, and the app slug when that differs (most installers
write the slug literally from a quoted heredoc, so a project installed under a
custom name still carries http://<slug>). The name must be whole: the next
character may not continue a hostname, so http://ghost never matches the front of
http://ghost-admin, http://ghost.example or http://ghost_db.

The IP rather than localhost:<port> because it is the one address that works from
the host on Linux AND from inside the Docker network on every OS, so the app's
own server-side calls to its public URL keep working. It is never worse than a
name that resolves nowhere.

The slug is left alone when it names some OTHER service in the compose (a
backend behind an nginx entry point): there http://<slug>:3000 is an internal
call to that container, and the project IP belongs to a different one.

Prints each changed file, relative to the project directory. Standard library
only -- macOS's python3 has no yaml.
"""
import os
import re
import sys

SKIP_DIRS = {".git", "node_modules", "vendor", ".venv", "venv", "__pycache__"}
SKIP_FILES = {"docker-compose.upstream.yaml"}
MAX_BYTES = 1024 * 1024
MAX_DEPTH = 3
NAME_CHARS = "A-Za-z0-9_.-"


def compose_service_blocks(text):
    """{service_key: block_text} for the services in a compose file, by indent."""
    lines = text.split("\n")
    si = next((i for i, l in enumerate(lines) if re.match(r"^services:\s*$", l)), None)
    if si is None:
        return {}
    blocks, current, indent = {}, None, None
    for line in lines[si + 1:]:
        if not line.strip() or line.lstrip().startswith("#"):
            if current:
                blocks[current].append(line)
            continue
        width = len(line) - len(line.lstrip())
        if width == 0:
            break
        if indent is None:
            indent = width
        m = re.match(r"^\s*([A-Za-z0-9._-]+):\s*$", line) if width == indent else None
        if m:
            current = m.group(1)
            blocks[current] = []
        elif current:
            blocks[current].append(line)
    return {k: "\n".join(v) for k, v in blocks.items()}


def slug_is_other_service(project_dir, slug):
    for fname in ("docker-compose.yaml", "docker-compose.yml"):
        path = os.path.join(project_dir, fname)
        if not os.path.isfile(path):
            continue
        try:
            blocks = compose_service_blocks(open(path, errors="replace").read())
        except Exception:
            return False
        for key, body in blocks.items():
            is_web = "ipv4_address" in body
            names_slug = key == slug or re.search(
                r"^\s*container_name:\s*[\"']?%s[\"']?\s*$" % re.escape(slug), body, re.M)
            if names_slug and not is_web:
                return True
    return False


def candidate_files(root, top_level_only):
    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        depth = 0 if rel == "." else rel.count(os.sep) + 1
        dirnames[:] = [d for d in dirnames
                       if d not in SKIP_DIRS and not top_level_only and depth + 1 < MAX_DEPTH]
        for f in filenames:
            if f in SKIP_FILES:
                continue
            if top_level_only and not (f.startswith(".env") or f.startswith("docker-compose.")):
                continue
            path = os.path.join(dirpath, f)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            try:
                if os.path.getsize(path) > MAX_BYTES:
                    continue
            except OSError:
                continue
            yield path


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    top_level_only = "--top-level-only" in sys.argv[1:]
    if len(args) < 3:
        sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
        sys.exit(2)
    root, ip, project = args[0], args[1], args[2]
    slug = args[3] if len(args) > 3 else ""
    if not ip or not os.path.isdir(root):
        return

    names = [project]
    if slug and slug != project and not slug_is_other_service(root, slug):
        names.append(slug)
    # Longest first, so a slug that is a prefix of the project name (or the
    # reverse) can never win a shorter match -- the lookahead already stops
    # that, this keeps it obvious.
    names.sort(key=len, reverse=True)
    url_re = re.compile(
        r"((?:https?|wss?)://)(?:%s)(?![%s])"
        % ("|".join(re.escape(n) for n in names), NAME_CHARS))

    for path in candidate_files(root, top_level_only):
        try:
            raw = open(path, "rb").read()
        except OSError:
            continue
        if b"\0" in raw[:8192]:
            continue
        text = raw.decode("utf-8", errors="surrogateescape")
        new = url_re.sub(lambda m: m.group(1) + ip, text)
        new = new.replace("__ZELTRO_IP__", ip).replace("__ZELTRO_PROJECT__", project)
        if new != text:
            with open(path, "wb") as fh:
                fh.write(new.encode("utf-8", errors="surrogateescape"))
            print(os.path.relpath(path, root))


if __name__ == "__main__":
    main()
