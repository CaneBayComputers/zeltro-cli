#!/usr/bin/env python3
"""Pre-answer an agent's first-run screens, so the first session goes straight to work.

    agent_firstrun.py AGENT

Each agent stores the answers itself once a user clicks through; this writes the
same keys ahead of time, only where the user hasn't answered already. Never
replaces a file it can't parse. Probed by running each CLI in a throwaway home
on a pseudo-terminal (2026-10-23):

  claude 2.1.309  theme / login wizard  -> hasCompletedOnboarding (+ lastOnboardingVersion),
                  only when signed in or run on a key; the wizard is the sign-in path otherwise.
                  "Detected a custom API key ... use it?" (ANTHROPIC_API_KEY) -> its last 20
                  characters in customApiKeyResponses.approved.
  codex 0.128     "Update available! ... Update now" -> check_for_update_on_startup = false
  gemini 0.65     "How would you like to authenticate?" -> security.auth.selectedType =
                  "gemini-api-key" (Zeltro runs Gemini on a key only)
  aider 0.86      .gitignore, release-notes, model-warning and analytics questions ->
                  ~/.aider.conf.yml keys (Zeltro hides .aider* in .git/info/exclude instead)
  hermes          "Help improve Hermes?" -> telemetry.shared_metrics.offer_version (via
                  `hermes config set`; sharing stays off, its default)
  qwen, opencode  nothing blocks when Zeltro passes the key.
  agy 1.4.6       nothing seeded. Its first interactive start asks for a color scheme,
                  then "Terms of Service & Data Use" with data sharing ticked by default:
                  a consent the user gives, so it's left to them. Headless runs (-p)
                  skip it. Folder trust: trustedWorkspaces (zeltro_trust_project_for_agents).

Folder trust is per project and lives in zeltro_trust_project_for_agents.
Best effort: exits 0 whatever happens.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time


def claude_global_config():
    d = os.environ.get("CLAUDE_CONFIG_DIR")
    return os.path.join(d, ".claude.json") if d else os.path.expanduser("~/.claude.json")


def update_json(path, change):
    """Apply change(data) -> bool (changed?) to a JSON file, atomically.

    Creates the file when missing. Leaves an unparseable file alone. Redoes the
    change if the agent rewrote the file meanwhile (Claude writes .claude.json
    on every start).
    """
    path = os.path.realpath(path)    # keep a symlinked dotfile a symlink
    for _ in range(5):
        before, data, mode = None, {}, 0o600
        if os.path.exists(path):
            try:
                st = os.stat(path)
                before, mode = st.st_mtime_ns, st.st_mode & 0o777
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
            except (OSError, ValueError):
                return False
            if not isinstance(data, dict):
                return False
        if not change(data):
            return False
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".zeltro-")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.chmod(tmp, mode)
        now = os.stat(path).st_mtime_ns if os.path.exists(path) else None
        if now != before:
            os.unlink(tmp)
            time.sleep(0.2)
            continue
        os.replace(tmp, path)
        return True
    return False


def run(cmd, timeout=20):
    try:
        p = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return None, ""


def claude():
    path = claude_global_config()
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    on_key = bool(key or os.environ.get("ANTHROPIC_AUTH_TOKEN"))
    state = {}

    def change(data):
        changed = False
        if data.get("hasCompletedOnboarding") is not True:
            # The wizard is how a subscription user signs in, so skip it only
            # once there's a sign-in or a key. Asked lazily: `claude auth status`
            # costs a process start, and this runs before every session.
            if "signed_in" not in state:
                rc, out = run(["claude", "auth", "status", "--json"])
                try:
                    state["signed_in"] = bool(json.loads(out).get("loggedIn"))
                except ValueError:
                    state["signed_in"] = False
            if on_key or state["signed_in"]:
                data["hasCompletedOnboarding"] = True
                if not data.get("lastOnboardingVersion"):
                    rc, out = run(["claude", "--version"])
                    v = out.split()[0] if rc == 0 and out.split() else ""
                    if v:
                        data["lastOnboardingVersion"] = v
                changed = True
        if key:
            # Claude keeps the key's last 20 characters as the answer.
            tail = key[-20:]
            resp = data.setdefault("customApiKeyResponses", {})
            approved = resp.setdefault("approved", [])
            resp.setdefault("rejected", [])
            if tail not in approved and tail not in resp["rejected"]:
                approved.append(tail)
                changed = True
        return changed

    update_json(path, change)


def codex():
    home = os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")
    # realpath: a key profile's managed CODEX_HOME links config.toml to ~/.codex's.
    path = os.path.realpath(os.path.join(home, "config.toml"))
    try:
        text = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    except OSError:
        return
    # Only a top-level key counts: everything before the first [table].
    top = re.split(r"(?m)^\s*\[", text, maxsplit=1)[0]
    if re.search(r"(?m)^\s*check_for_update_on_startup\s*=", top):
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".zeltro-tmp", "w", encoding="utf-8") as f:
        f.write("# Zeltro: no update picker on startup (`zeltro update` / npm handle updates).\n"
                "check_for_update_on_startup = false\n" + ("\n" if text and not text.startswith("\n") else "") + text)
    if os.path.exists(path):
        os.chmod(path + ".zeltro-tmp", os.stat(path).st_mode & 0o777)
    os.replace(path + ".zeltro-tmp", path)


def gemini():
    path = os.path.expanduser("~/.gemini/settings.json")

    def change(data):
        auth = data.setdefault("security", {}).setdefault("auth", {})
        if auth.get("selectedType"):
            return False
        auth["selectedType"] = "gemini-api-key"
        return True

    update_json(path, change)


AIDER_KEYS = [
    ("gitignore", "false"),            # "Add .aider* to .gitignore?" (Zeltro excludes it locally)
    ("show-release-notes", "false"),   # "Would you like to see what's new in this version?"
    ("show-model-warnings", "false"),  # "Unknown context window size ... Open documentation url?"
    ("check-update", "false"),         # "Newer aider version available" prompt
    ("analytics-disable", "true"),     # the analytics opt-in some users are asked
]


def aider():
    path = os.path.expanduser("~/.aider.conf.yml")
    try:
        text = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    except OSError:
        return
    missing = [(k, v) for k, v in AIDER_KEYS if not re.search(r"(?m)^\s*%s\s*:" % re.escape(k), text)]
    if not missing:
        return
    add = "".join("%s: %s\n" % kv for kv in missing)
    if text and not text.endswith("\n"):
        text += "\n"
    with open(path, "w", encoding="utf-8") as f:
        f.write(text + ("# Zeltro: answers to aider's first-run questions\n" if not text else "") + add)


# The "Help improve Hermes?" question asks again whenever the recorded
# offer_version is below the current one ("Asking once more ..."); 2 as of
# 2026-10-23. Answering "No thanks" writes telemetry.shared_metrics.offer_version
# with sharing left off, which is also the default.
HERMES_OFFER_VERSION = 2


def hermes():
    home = os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes")
    path = os.path.join(home, "config.yaml")
    # No config means Hermes was never set up here (or this is a throwaway
    # HOME): don't start it. Run under another HOME, Hermes rewrites the shared
    # install's launchers to that HOME.
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return
    m = re.search(r"(?m)^\s+offer_version:\s*(\d+)", text)
    if m and int(m.group(1)) >= HERMES_OFFER_VERSION:
        return
    # Hermes's own setter keeps the file's comments and layout.
    run(["hermes", "config", "set", "telemetry.shared_metrics.offer_version", str(HERMES_OFFER_VERSION)], timeout=60)


AGENTS = {"claude": claude, "codex": codex, "gemini": gemini, "aider": aider, "hermes": hermes}


def main(argv):
    if len(argv) != 1 or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    fn = AGENTS.get(argv[0])
    if fn:
        try:
            fn()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
