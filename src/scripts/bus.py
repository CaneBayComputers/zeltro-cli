#!/usr/bin/env python3
"""zeltro peers / zeltro send -- messages between agent sessions.

The Zeltro app (GUI) hosts one agent session per project, possibly on several
hosts, and is the only thing that sees them all, so it does the routing. This
side only reads what the app publishes and drops messages where it collects
them. Everything lives in a per-user spool, so nothing here needs sudo:

  ~/.zeltro/bus/peers.json   written by the app (tmp + rename) whenever sessions
                             change, plus a heartbeat every 30s:
                             {"version": 1, "updated_at": "<ISO8601 UTC>",
                              "this_host": "<name>", "sessions": [{"project",
                              "host", "agent", "profile", "started_at"}, ...]}
  ~/.zeltro/bus/outbox/      one <epoch_ms>-<pid>-<rand>.json per send, written
                             as .json.tmp then renamed; the app ignores *.tmp,
                             delivers the rest into the targets' terminals and
                             deletes them.

Addresses are project@host. A bare project is accepted when only one live
session has that name. Python 3.6+ only (macOS ships 3.9).
"""

import json
import os
import random
import sys
import time
from datetime import datetime, timezone

VERSION = 1
STALE_AFTER = 90          # seconds without a heartbeat before the app counts as gone
MAX_BODY = 16 * 1024      # bytes, UTF-8

BUS = os.environ.get("ZELTRO_BUS_DIR") or os.path.join(os.path.expanduser("~"), ".zeltro", "bus")
PEERS = os.path.join(BUS, "peers.json")
OUTBOX = os.path.join(BUS, "outbox")
JSON_OUT = os.environ.get("JSON_OUTPUT") == "1"

SEND_USAGE = """Usage: zeltro send <project>[@host] [<project>[@host] ...] -- <message...>
       zeltro send --all -- <message...>
       zeltro send <project>[@host] <message...>      (one target: no -- needed)

Send a message to other agent sessions running in the Zeltro app. Use - as the
message to read it from stdin. The app types it into each target's terminal as:

  [Zeltro message from <you>@<host> to <others>] <message>

Every target must be a live session (see: zeltro peers), or nothing is sent.
--all sends to every live session except you. Messages are capped at 16 KB.
Run it from inside your project directory; that is how you are identified.
Exit 0 means queued: the app delivers it, and tells you if a target has gone."""

PEERS_USAGE = """Usage: zeltro peers

List the agent sessions running in the Zeltro app, on every host, and mark
which one is you. Message them with: zeltro send <project>[@host] ... -- "..." """


def now_iso():
    t = datetime.now(timezone.utc)
    return t.strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (t.microsecond // 1000)


def emit_json(obj):
    print(json.dumps(obj))


def fail(action, code, message, extra=None):
    if JSON_OUT:
        obj = {"action": action, "status": "error", "error": code, "message": message}
        obj.update(extra or {})
        emit_json(obj)
    else:
        print("zeltro %s: %s" % (action, message), file=sys.stderr)
        live = (extra or {}).get("live_peers")
        if live is not None:
            if live:
                print("Live sessions: " + ", ".join(live), file=sys.stderr)
            else:
                print("There are no other live sessions.", file=sys.stderr)
    sys.exit(1)


def ensure_bus():
    os.makedirs(OUTBOX, mode=0o700, exist_ok=True)
    for d in (BUS, OUTBOX):
        try:
            os.chmod(d, 0o700)
        except OSError:
            pass


def load_peers():
    """(data, error). data is None when the app has never written the file."""
    try:
        with open(PEERS, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return None, None
    except (OSError, ValueError) as e:
        return None, "cannot read %s: %s" % (PEERS, e)
    if not isinstance(data, dict) or not isinstance(data.get("sessions", []), list):
        return None, "%s is not in the expected format" % PEERS
    return data, None


def age_seconds(data):
    """Seconds since the app last wrote peers.json, or None if unknown."""
    stamp = str(data.get("updated_at") or "")
    try:
        t = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        if t.tzinfo is None:
            t = t.replace(tzinfo=timezone.utc)
        return max(0, int((datetime.now(timezone.utc) - t).total_seconds()))
    except ValueError:
        return None


def this_host(data):
    if data and data.get("this_host"):
        return str(data["this_host"])
    return os.uname()[1].split(".")[0]


def sessions_of(data):
    out = []
    for s in (data or {}).get("sessions", []):
        if isinstance(s, dict) and s.get("project") and s.get("host"):
            out.append(s)
    return out


def addr(s):
    return "%s@%s" % (s["project"], s["host"])


def my_project():
    """The project the caller is working in, from its directory, or None."""
    root = os.environ.get("ZELTRO_PROJECTS_DIR", "")
    if not root:
        return None
    root = os.path.realpath(root)
    try:
        cwd = os.path.realpath(os.getcwd())
    except OSError:
        return None
    rel = os.path.relpath(cwd, root)
    if rel == "." or rel.startswith(".."):
        return None
    name = rel.split(os.sep)[0]
    return name if os.path.isdir(os.path.join(root, name)) else None


def cmd_peers(args):
    if any(a in ("-h", "--help") for a in args):
        print(PEERS_USAGE)
        return 0
    if args:
        fail("peers", "usage", "unexpected argument: %s" % args[0])

    data, err = load_peers()
    if err:
        fail("peers", "peers_unreadable", err)
    host = this_host(data)
    me = my_project()
    me_addr = "%s@%s" % (me, host) if me else None
    age = age_seconds(data) if data else None
    running = data is not None and age is not None and age <= STALE_AFTER

    rows = []
    for s in sessions_of(data):
        rows.append({
            "address": addr(s), "project": s["project"], "host": s["host"],
            "agent": s.get("agent", ""), "profile": s.get("profile", ""),
            "started_at": s.get("started_at", ""), "is_me": addr(s) == me_addr,
        })

    if JSON_OUT:
        emit_json({"action": "peers", "status": "success", "version": VERSION,
                   "this_host": host, "me": me_addr, "app_running": running,
                   "updated_at": (data or {}).get("updated_at"), "age_seconds": age,
                   "sessions": rows})
        return 0

    if data is None:
        print("No agent sessions: the Zeltro app has not published any on this host")
        print("(%s does not exist). Is the app running?" % PEERS)
        return 0
    if not running:
        when = "%ds ago" % age if age is not None else "at an unknown time"
        print("WARNING: the Zeltro app doesn't appear to be running (last update %s)." % when)
        print("These sessions may be gone, and messages sent now wait until it is back.")
        print()
    if not rows:
        print("No agent sessions are running in the Zeltro app.")
    else:
        print("Agent sessions (this host: %s):" % host)
        width = max(len(r["address"]) for r in rows)
        for r in rows:
            who = r["agent"] + (" (%s)" % r["profile"] if r["profile"] else "")
            print("  %s %-*s  %s%s" % ("*" if r["is_me"] else " ", width, r["address"],
                                      who, "   <- you" if r["is_me"] else ""))
    if me_addr is None:
        print()
        print("You are not inside a project directory, so you cannot send from here.")
    print()
    print('Send with: zeltro send <project>[@host] ... -- "message"   (or --all)')
    return 0


def parse_send_args(args):
    """-> (targets, all_flag, body_words)."""
    all_flag = False
    if "--" in args:
        i = args.index("--")
        head, body = args[:i], args[i + 1:]
    else:
        # Legacy one-target form: the first word is the target, the rest is the
        # body. With --all there is no target word at all.
        lead = [a for a in args if a == "--all"]
        rest = [a for a in args if a != "--all"] if lead else args
        if lead:
            head, body = ["--all"], rest
        else:
            head, body = rest[:1], rest[1:]
    targets = []
    for a in head:
        if a == "--all":
            all_flag = True
        elif a.startswith("-") and a != "-":
            fail("send", "usage", "unknown option %s (put the message after --)" % a)
        else:
            targets.append(a)
    return targets, all_flag, body


def cmd_send(args):
    if not args or any(a in ("-h", "--help") for a in args[:1]) or \
            ("--" in args and any(a in ("-h", "--help") for a in args[:args.index("--")])):
        print(SEND_USAGE)
        return 0 if args else 1

    targets, all_flag, body_words = parse_send_args(args)
    if all_flag and targets:
        fail("send", "usage", "use --all or a list of targets, not both")
    if not all_flag and not targets:
        fail("send", "usage", "no target given. " + SEND_USAGE.splitlines()[0])

    if body_words == ["-"]:
        body = sys.stdin.read()
        if body.endswith("\n"):
            body = body[:-1]
    else:
        body = " ".join(body_words)
    if not body.strip():
        fail("send", "empty_body", "the message is empty")
    size = len(body.encode("utf-8"))
    if size > MAX_BODY:
        fail("send", "body_too_large", "the message is %d bytes; the limit is %d" % (size, MAX_BODY))

    me = my_project()
    if not me:
        fail("send", "not_in_project",
             "run this from inside your project directory (under %s); that is how the "
             "recipient knows who sent it" % (os.environ.get("ZELTRO_PROJECTS_DIR") or "the projects dir"))

    data, err = load_peers()
    if err:
        fail("send", "peers_unreadable", err)
    if data is None:
        fail("send", "app_not_running",
             "no agent sessions are published on this host (%s does not exist). "
             "The Zeltro app has to be running to deliver messages." % PEERS)

    host = this_host(data)
    me_addr = "%s@%s" % (me, host)
    live = [addr(s) for s in sessions_of(data)]
    others = [a for a in live if a != me_addr]

    if all_flag:
        resolved = others
        if not resolved:
            fail("send", "no_peers", "there are no other live sessions to send to",
                 {"live_peers": others})
    else:
        resolved, bad = [], []
        for t in targets:
            if "@" in t:
                hits = [a for a in live if a == t]
            else:
                hits = [a for a in live if a.split("@", 1)[0] == t]
            if len(hits) > 1:
                bad.append("%s (ambiguous: %s)" % (t, ", ".join(hits)))
            elif not hits:
                bad.append("%s (not a live session)" % t)
            elif hits[0] == me_addr:
                bad.append("%s (that is you)" % t)
            elif hits[0] not in resolved:
                resolved.append(hits[0])
        if bad:
            fail("send", "bad_targets", "nothing sent. Bad target%s: %s"
                 % ("s" if len(bad) > 1 else "", "; ".join(bad)),
                 {"bad_targets": bad, "live_peers": others})

    ensure_bus()
    stem = "%d-%d-%06x" % (int(time.time() * 1000), os.getpid(), random.getrandbits(24))
    msg = {"version": VERSION, "id": stem, "from": {"project": me, "host": host},
           "to": resolved, "body": body, "sent_at": now_iso()}
    final = os.path.join(OUTBOX, stem + ".json")
    tmp = final + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(msg, f)
        f.write("\n")
    os.replace(tmp, final)

    age = age_seconds(data)
    running = age is not None and age <= STALE_AFTER
    if JSON_OUT:
        out = {"action": "send", "status": "success", "id": stem, "from": me_addr,
               "to": resolved, "file": final, "app_running": running}
        emit_json(out)
    else:
        print("Queued for %s. The Zeltro app types it into %s terminal%s." % (
            ", ".join(resolved), "their" if len(resolved) > 1 else "its",
            "s" if len(resolved) > 1 else ""))
        print("Replies arrive in yours as a [Zeltro message from ...] line.")
    if not running:
        print("Warning: the Zeltro app doesn't appear to be running (no heartbeat for %s). "
              "The message is queued, but nothing delivers it until the app is back."
              % ("%ds" % age if age is not None else "an unknown time"), file=sys.stderr)
    return 0


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("peers", "send"):
        print("usage: bus.py peers|send ...", file=sys.stderr)
        return 2
    cmd, args = sys.argv[1], sys.argv[2:]
    return cmd_peers(args) if cmd == "peers" else cmd_send(args)


if __name__ == "__main__":
    sys.exit(main())
