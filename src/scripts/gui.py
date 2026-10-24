#!/usr/bin/env python3
"""zeltro gui <action> -- ask the Zeltro app to do something for an agent.

An agent running in the Zeltro app can ask it to show a question, collect a
secret, raise a notification, open a URL or a settings tab, and tell it when a
turn ends. Requests go through the same per-user spool as `zeltro send`:

  <bus>/gui/requests/<id>.json   written here (tmp + rename), read and deleted
                                 by the app, which polls every 1.5s:
                                 {"version": 1, "id", "action", "args": {...},
                                  "from": {"project", "host", "session"},
                                  "sent_at": "<ISO8601 UTC>"}
  <bus>/gui/cancel/<id>          written here when the caller gives up (timeout,
                                 Ctrl-C) after the app already took the request,
                                 so the app can close its dialog. Empty file.
  <bus>/gui/replies/<id>.json    written by the app for actions that wait:
                                 {"version": 1, "id", "status": "ok" | "declined"
                                  | "refused" | "error", "result": {...},
                                  "error": "<text>"}
                                 read and deleted here.

The app deletes anything older than 10 minutes from both directories, which
covers a caller killed while it waited. It deletes cancel/ files too. Files are 0600, directories 0700: a
secret's value passes through a reply file.

Exit codes: 0 ok, 1 error, 2 usage, 3 the app is not available (ask in the chat
instead), 4 timed out, 5 the user declined or cancelled, 6 the app refused.
`event` is the exception: it always exits 0, because the agents run it as a
hook and a failing Claude Stop hook blocks the stop.
"""

import json
import os
import random
import re
import signal
import sys
import time

sys.dont_write_bytecode = True   # no __pycache__ in the install dir
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bus  # noqa: E402  (peers.json reading, project detection, timestamps)


def _projects_dir_from_env_file():
    """`zeltro gui event` skips functions.sh to stay fast, so read PROJECTS_DIR
    the way get_projects_dir does: the first PROJECTS_DIR= line, quotes and a
    leading ~ handled."""
    try:
        with open("/etc/zeltro-cli/.env", encoding="utf-8") as f:
            for line in f:
                if line.startswith("PROJECTS_DIR="):
                    v = line.split("=", 1)[1].strip().strip('"')
                    return os.path.expanduser(v) if v else ""
    except OSError:
        pass
    return ""


if not os.environ.get("ZELTRO_PROJECTS_DIR"):
    os.environ["ZELTRO_PROJECTS_DIR"] = _projects_dir_from_env_file()

VERSION = 1
GUI = os.path.join(bus.BUS, "gui")
REQUESTS = os.path.join(GUI, "requests")
REPLIES = os.path.join(GUI, "replies")
CANCELS = os.path.join(GUI, "cancel")
JSON_OUT = bus.JSON_OUT
POLL = 0.25
EVENT_GAP = 2.0           # seconds: at most one event of a type per session this often
STATUS_MAX = 2000         # characters the app shows for a status
MESSAGE_MAX = 4000        # characters of the agent's last reply sent with turn-done

EXIT_OK, EXIT_ERROR, EXIT_USAGE, EXIT_NO_APP, EXIT_TIMEOUT, EXIT_DECLINED, EXIT_REFUSED = 0, 1, 2, 3, 4, 5, 6
STATUS_EXIT = {"ok": EXIT_OK, "declined": EXIT_DECLINED, "refused": EXIT_REFUSED, "error": EXIT_ERROR}

TABS = ("general", "appearance", "services", "remotes", "ai", "github")
LEVELS = ("info", "warning", "danger")
EVENTS = ("turn-done", "needs-input", "build-done")
DEFAULT_TIMEOUT = {"ask": 300, "secret": 300, "open": 120, "settings": 15, "screenshot": 30, "report": 15}
REPORT_TITLE_MAX, REPORT_DETAILS_MAX = 200, 4000

USAGE = """Usage: zeltro gui <action> [args] [--timeout <seconds>]

Ask the Zeltro app to do something for you. Only works in a session the app
started; anywhere else it exits 3, so ask in the chat instead.

  zeltro gui ask "<question>" --option <text> [--option <text> ...] [--default <text>] [--allow-text]
        Show a question with 1-6 answers. Prints the chosen answer. --allow-text
        also lets the user type their own answer (then --option is optional).
  zeltro gui secret <NAME> [--file .env] [--reason "<why>"]
        Ask the user for a secret (an API key, a password) and write NAME=<value>
        into that file in the project. The value is never printed.
  zeltro gui notify [--level info|warning|danger] "<title>" ["<message>"]
        Show a notification. Does not wait.
  zeltro gui open <http(s) url> | --project
        Open a URL, or the project's own address, in the user's browser.
  zeltro gui settings <general|appearance|services|remotes|ai|github> [--reason "<why>"]
        Open a settings tab, e.g. when a key or remote has to be added there.
  zeltro gui preview [--path /page]
        Reload this session's app preview, or open that page of the project's
        site in it. Does not wait.
  zeltro gui screenshot [--path /page]
        Capture this session's app preview (that page first, with --path) as a
        PNG in .zeltro-uploads/. Prints the file's path.
  zeltro gui report "<what went wrong>" [--details "<what you ran, what happened>"]
        Report a bug in Zeltro itself (not the project) to its developers.
  zeltro gui status "<text>"
        Show the user, in the app's panel, what you're doing or what changed.
        One or two plain sentences. Does not wait.
  zeltro gui event <turn-done|needs-input|build-done>
        Tell the app a turn ended or needs the user. Always exits 0.

Exit codes: 0 ok, 1 error, 2 usage, 3 app not available (ask in the chat),
4 timed out, 5 the user declined or cancelled, 6 the app refused."""


class Usage(Exception):
    pass


def out(status, gui_action, message=None, **extra):
    """Human line (stdout for ok, stderr otherwise) or one JSON object."""
    if JSON_OUT:
        obj = {"action": "gui", "gui_action": gui_action, "status": status}
        if message:
            obj["message"] = message
        obj.update(extra)
        print(json.dumps(obj))
    elif message:
        print(message, file=sys.stdout if status == "success" else sys.stderr)


def finish(code, gui_action, message):
    status = {EXIT_OK: "success", EXIT_TIMEOUT: "timeout", EXIT_DECLINED: "declined",
              EXIT_REFUSED: "refused", EXIT_NO_APP: "no_app", EXIT_USAGE: "usage"}.get(code, "error")
    out(status, gui_action, ("zeltro gui %s: %s" % (gui_action, message)) if code else message)
    return code


# --- the bus -----------------------------------------------------------------

def app_problem():
    """Why the app can't take a request here, or None when it can."""
    data, err = bus.load_peers()
    if err:
        return err
    if data is None:
        return "the Zeltro app is not running on this host"
    age = bus.age_seconds(data)
    if age is None or age > bus.STALE_AFTER:
        return "the Zeltro app doesn't appear to be running (no heartbeat for %s)" % (
            "%ds" % age if age is not None else "an unknown time")
    return None


def ensure_dirs():
    for d in (bus.BUS, GUI, REQUESTS, REPLIES, CANCELS):
        os.makedirs(d, mode=0o700, exist_ok=True)
        try:
            os.chmod(d, 0o700)
        except OSError:
            pass


def write_json(path, obj):
    tmp = "%s.%d.tmp" % (path, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(obj, f)
        f.write("\n")
    os.replace(tmp, path)


def new_id():
    return "%d-%d-%06x" % (int(time.time() * 1000), os.getpid(), random.getrandbits(24))


def sender():
    data, _ = bus.load_peers()
    return {"project": bus.my_project() or "", "host": bus.this_host(data),
            "session": os.environ.get("ZELTRO_GUI_SESSION", "")}


def send_request(action, args):
    ensure_dirs()
    rid = new_id()
    write_json(os.path.join(REQUESTS, rid + ".json"),
               {"version": VERSION, "id": rid, "action": action, "args": args,
                "from": sender(), "sent_at": bus.now_iso()})
    return rid


def discard(path):
    try:
        os.unlink(path)
    except OSError:
        pass


def withdraw(rid):
    """Take a request back. If the app hasn't picked it up yet, deleting it is
    enough; if it has, a dialog may be open, so leave a cancel marker for it."""
    req = os.path.join(REQUESTS, rid + ".json")
    try:
        os.unlink(req)
        return
    except FileNotFoundError:
        pass
    except OSError:
        return
    try:
        fd = os.open(os.path.join(CANCELS, rid), os.O_WRONLY | os.O_CREAT, 0o600)
        os.close(fd)
    except OSError:
        pass


def wait_reply(rid, timeout):
    """-> reply dict, or None on timeout. Withdraws the request if it gives up."""
    rep = os.path.join(REPLIES, rid + ".json")

    def interrupted(*_):
        withdraw(rid)
        sys.exit(130)
    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)

    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(rep, encoding="utf-8") as f:
                reply = json.load(f)
        except (FileNotFoundError, ValueError):
            # ValueError: caught mid-write by an app that doesn't rename. Retry.
            time.sleep(POLL)
            continue
        discard(rep)
        return reply if isinstance(reply, dict) else {"status": "error", "error": "malformed reply"}
    # Nobody answered: take the question back so the app doesn't show it late,
    # or close it if it's already showing.
    withdraw(rid)
    return None


def request(action, args, timeout):
    """Send, wait, and map the reply. -> (exit code, result dict, error text)."""
    problem = app_problem()
    if problem:
        return EXIT_NO_APP, {}, problem + ". Ask the user in the chat instead."
    rid = send_request(action, args)
    reply = wait_reply(rid, timeout)
    if reply is None:
        return EXIT_TIMEOUT, {}, "no answer from the Zeltro app within %ds" % timeout
    status = str(reply.get("status", "error"))
    code = STATUS_EXIT.get(status, EXIT_ERROR)
    result = reply.get("result") if isinstance(reply.get("result"), dict) else {}
    err = str(reply.get("error") or "")
    if code == EXIT_DECLINED and not err:
        err = "the user declined"
    elif code == EXIT_REFUSED and not err:
        err = "the Zeltro app refused the request"
    elif code == EXIT_ERROR and not err:
        err = "the Zeltro app reported an error"
    return code, result, err


def require_session(action):
    if not os.environ.get("ZELTRO_GUI_SESSION"):
        raise NoApp("this is not a session the Zeltro app started, so nobody is watching "
                    "the app to answer. Ask the user in the chat instead.")


class NoApp(Exception):
    pass


# --- argument parsing --------------------------------------------------------

def parse(argv, flags, multi=()):
    """Tiny parser: --flag value options (repeatable ones in multi), bare
    --switches (value None in flags), and positionals. -> (opts, positionals)."""
    opts = {m: [] for m in multi}
    pos = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--":
            pos.extend(argv[i + 1:])
            break
        if a.startswith("--") and a != "--":
            name, eq, val = a[2:].partition("=")
            if name not in flags:
                raise Usage("unknown option --%s" % name)
            if flags[name] is None:          # switch
                opts[name] = True
            else:
                if not eq:
                    i += 1
                    if i >= len(argv):
                        raise Usage("--%s needs a value" % name)
                    val = argv[i]
                if name in multi:
                    opts[name].append(val)
                else:
                    opts[name] = val
        else:
            pos.append(a)
        i += 1
    return opts, pos


def timeout_of(action, opts):
    raw = opts.get("timeout")
    if raw is None:
        return DEFAULT_TIMEOUT[action]
    try:
        t = int(raw)
    except ValueError:
        raise Usage("--timeout takes whole seconds")
    if t < 1 or t > 3600:
        raise Usage("--timeout must be between 1 and 3600 seconds")
    return t


# --- actions -----------------------------------------------------------------

def cmd_ask(argv):
    opts, pos = parse(argv, {"option": "", "default": "", "timeout": "", "allow-text": None},
                      multi=("option",))
    if len(pos) != 1 or not pos[0].strip():
        raise Usage('give the question as one quoted argument: zeltro gui ask "<question>" --option ...')
    options = [o for o in opts["option"] if o.strip()]
    allow_text = bool(opts.get("allow-text"))
    if not (0 if allow_text else 1) <= len(options) <= 6:
        raise Usage("give between 1 and 6 --option answers" +
                    ("" if allow_text else ", or --allow-text for a typed answer"))
    if len(set(options)) != len(options):
        raise Usage("the --option answers must be different")
    args = {"question": pos[0], "options": options}
    if allow_text:
        # The app adds a text box. An app older than this refuses an ask with
        # no options and ignores the flag otherwise.
        args["allow_text"] = True
    if "default" in opts:
        if opts["default"] not in options:
            raise Usage("--default must be one of the --option answers")
        args["default"] = opts["default"]
    timeout = timeout_of("ask", opts)
    require_session("ask")
    code, result, err = request("ask", args, timeout)
    if code:
        return finish(code, "ask", err)
    answer = result.get("answer")
    typed = allow_text and result.get("typed") is True
    if not isinstance(answer, str) or not (answer.strip() if typed else answer in options):
        return finish(EXIT_ERROR, "ask", "the Zeltro app returned an answer that isn't one of the options")
    if JSON_OUT:
        out("success", "ask", answer=answer, typed=typed)
    else:
        print(answer)
    return EXIT_OK


NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
PLAIN_RE = re.compile(r"^[A-Za-z0-9_./:@+=,%-]*$")


def project_root():
    me = bus.my_project()
    if not me:
        return None
    return os.path.realpath(os.path.join(os.environ.get("ZELTRO_PROJECTS_DIR", ""), me))


def resolve_in_project(root, rel):
    """The real path of rel inside root, or None if it would land outside it
    (absolute paths, .., or a symlink pointing out)."""
    if not rel or os.path.isabs(rel):
        return None
    path = os.path.realpath(os.path.join(root, rel))
    if path != root and path.startswith(root + os.sep) and not os.path.isdir(path):
        return path
    return None


def env_quote(value):
    """A .env value that phpdotenv, python-dotenv and Node's dotenv all read back
    unchanged. Single quotes are literal in all three."""
    if PLAIN_RE.match(value):
        return value
    if "'" not in value:
        return "'%s'" % value
    return '"%s"' % value.replace("\\", "\\\\").replace('"', '\\"')


def upsert_env(path, name, value):
    line = "%s=%s\n" % (name, env_quote(value))
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
        mode = os.stat(path).st_mode & 0o777
    except FileNotFoundError:
        lines, mode = [], 0o600
    pat = re.compile(r"^\s*(export\s+)?%s\s*=" % re.escape(name))
    done = False
    for i, l in enumerate(lines):
        if pat.match(l):
            if not done:
                lines[i] = line
                done = True
            else:
                lines[i] = None        # a duplicate would shadow or be shadowed
    lines = [l for l in lines if l is not None]
    if not done:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.append(line)
    tmp = "%s.zeltro-%d.tmp" % (path, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.writelines(lines)
    os.chmod(tmp, mode)
    os.replace(tmp, path)
    return done


def git_tracks(root, path):
    """True when the file is in a git repo and not ignored, so the secret would
    be committed with the next `git add`."""
    import subprocess
    try:
        inside = subprocess.run(["git", "-C", root, "rev-parse", "--is-inside-work-tree"],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=5)
        if inside.returncode != 0:
            return False
        ignored = subprocess.run(["git", "-C", root, "check-ignore", "-q", path],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        return ignored.returncode != 0
    except (OSError, subprocess.SubprocessError):
        return False


def cmd_secret(argv):
    opts, pos = parse(argv, {"file": "", "reason": "", "timeout": ""})
    if len(pos) != 1:
        raise Usage("give exactly one variable name: zeltro gui secret <NAME>")
    name = pos[0]
    if not NAME_RE.match(name):
        raise Usage("%s is not a valid variable name (letters, digits and _, not starting with a digit)" % name)
    rel = opts.get("file") or ".env"
    timeout = timeout_of("secret", opts)
    root = project_root()
    if not root:
        return finish(EXIT_ERROR, "secret", "run this from inside your project directory; "
                      "the secret is written into a file there")
    path = resolve_in_project(root, rel)
    if not path:
        return finish(EXIT_REFUSED, "secret", "%s is not a file inside the project" % rel)
    require_session("secret")
    args = {"name": name, "file": os.path.relpath(path, root)}
    if opts.get("reason"):
        args["reason"] = opts["reason"]
    code, result, err = request("secret", args, timeout)
    if code:
        return finish(code, "secret", err)
    value = result.get("value")
    if not isinstance(value, str) or value == "":
        return finish(EXIT_ERROR, "secret", "the Zeltro app returned no value")
    if "\n" in value or "\r" in value:
        return finish(EXIT_ERROR, "secret", "multi-line values can't go in a .env file; "
                      "ask the user to save it as a file in the project instead")
    replaced = upsert_env(path, name, value)
    value = None
    shown = os.path.relpath(path, root)
    msg = "%s %s in %s." % ("Updated" if replaced else "Set", name, shown)
    if JSON_OUT:
        out("success", "secret", msg, name=name, file=shown, replaced=replaced)
    else:
        print(msg)
    if git_tracks(root, path):
        print("Warning: %s is not ignored by git. Add it to .gitignore before committing, "
              "or the secret goes with it." % shown, file=sys.stderr)
    return EXIT_OK


def cmd_notify(argv):
    opts, pos = parse(argv, {"level": "", "event": ""})
    level = opts.get("level") or "info"
    if level not in LEVELS:
        raise Usage("--level must be one of: %s" % ", ".join(LEVELS))
    if not 1 <= len(pos) <= 2 or not pos[0].strip():
        raise Usage('zeltro gui notify [--level ...] "<title>" ["<message>"]')
    args = {"level": level, "title": pos[0]}
    if len(pos) == 2:
        args["message"] = pos[1]
    if opts.get("event"):
        args["event"] = opts["event"]
    problem = app_problem()
    if problem:
        return finish(EXIT_NO_APP, "notify", problem)
    send_request("notify", args)
    return finish(EXIT_OK, "notify", "Sent to the Zeltro app.")


def cmd_open(argv):
    opts, pos = parse(argv, {"project": None, "timeout": ""})
    timeout = timeout_of("open", opts)
    if opts.get("project"):
        if pos:
            raise Usage("use a URL or --project, not both")
        if not bus.my_project():
            return finish(EXIT_ERROR, "open", "--project needs to be run from inside your project directory")
        args = {"project": True}
    else:
        if len(pos) != 1:
            raise Usage("zeltro gui open <http(s) url> | --project")
        if not re.match(r"^https?://[^\s]+$", pos[0], re.I):
            return finish(EXIT_REFUSED, "open", "only http:// and https:// URLs can be opened")
        args = {"url": pos[0]}
    code, _result, err = request("open", args, timeout)
    return finish(code, "open", err if code else "Opened.")


def cmd_settings(argv):
    opts, pos = parse(argv, {"reason": "", "timeout": ""})
    if len(pos) != 1 or pos[0] not in TABS:
        raise Usage("zeltro gui settings <%s>" % "|".join(TABS))
    args = {"tab": pos[0]}
    if opts.get("reason"):
        args["reason"] = opts["reason"]
    code, _result, err = request("settings", args, timeout_of("settings", opts))
    return finish(code, "settings", err if code else "The %s settings are open in the Zeltro app." % pos[0])


def cmd_preview(argv):
    """Fire and forget, like notify: the app sends no reply. An app too old for
    it refuses into the void, which is fine; the caller never waits."""
    opts, pos = parse(argv, {"path": ""})
    if pos:
        raise Usage("zeltro gui preview [--path /page]")
    args = {}
    if "path" in opts:
        args["path"] = page_path(opts)
    require_session("preview")
    problem = app_problem()
    if problem:
        return finish(EXIT_NO_APP, "preview", problem)
    send_request("preview", args)
    return finish(EXIT_OK, "preview", "Sent to the Zeltro app.")


def page_path(opts):
    """--path for preview and screenshot: a page of the project's own site."""
    path = opts["path"]
    if not path.startswith("/") or path.startswith("//") or re.search(r"\s", path):
        raise Usage("--path takes a page of the project's site, starting with /, e.g. --path /pricing")
    return path


def cmd_screenshot(argv):
    """Waits: the app loads the page (if --path), captures it and replies with
    the PNG it saved in the project's .zeltro-uploads/."""
    opts, pos = parse(argv, {"path": "", "timeout": ""})
    if pos:
        raise Usage("zeltro gui screenshot [--path /page]")
    args = {"path": page_path(opts)} if "path" in opts else {}
    timeout = timeout_of("screenshot", opts)
    require_session("screenshot")
    code, result, err = request("screenshot", args, timeout)
    if code:
        return finish(code, "screenshot", err)
    rel = result.get("file")
    if not isinstance(rel, str) or not rel:
        return finish(EXIT_ERROR, "screenshot", "the Zeltro app returned no file")
    url = result.get("url") if isinstance(result.get("url"), str) else ""
    if JSON_OUT:
        out("success", "screenshot", file=rel, url=url)
    else:
        print(rel)
    return EXIT_OK


def cmd_report(argv):
    """A bug in Zeltro itself, sent to its error tracker by the app (scrubbed,
    project name removed). Not for the project's own bugs."""
    opts, pos = parse(argv, {"details": "", "timeout": ""})
    if len(pos) != 1 or not pos[0].strip():
        raise Usage('zeltro gui report "<what went wrong>" [--details "<what you ran, what happened>"]')
    args = {"title": pos[0].strip()[:REPORT_TITLE_MAX]}
    if opts.get("details", "").strip():
        args["details"] = opts["details"].strip()[:REPORT_DETAILS_MAX]
    timeout = timeout_of("report", opts)
    require_session("report")
    code, result, err = request("report", args, timeout)
    if code:
        return finish(code, "report", err)
    return finish(EXIT_OK, "report", "Reported to the Zeltro developers.")


def cmd_status(argv):
    """Fire and forget, like notify: the text goes to the app's panel."""
    opts, pos = parse(argv, {})
    if len(pos) != 1 or not pos[0].strip():
        raise Usage('zeltro gui status "<what you are doing, or what changed>"')
    text = pos[0].strip()
    if len(text) > STATUS_MAX:
        text = text[:STATUS_MAX - 1].rstrip() + "\u2026"
    require_session("status")
    problem = app_problem()
    if problem:
        return finish(EXIT_NO_APP, "status", problem)
    send_request("status", {"text": text})
    return finish(EXIT_OK, "status", "Sent to the Zeltro app.")


def _hook_stdin():
    """The JSON a hook gets on stdin (Claude Code), or {}. Never blocks: a
    terminal or a pipe nobody writes to just gives {}."""
    import select
    try:
        if sys.stdin is None or sys.stdin.isatty():
            return {}
        ready, _, _ = select.select([sys.stdin], [], [], 0.5)
        if not ready:
            return {}
        data = json.loads(sys.stdin.read(4 * 1024 * 1024) or "{}")
        return data if isinstance(data, dict) else {}
    except Exception:  # noqa: BLE001
        return {}


def _last_reply_from_transcript(path):
    """The text of the last assistant message in a Claude Code transcript
    (JSONL), for versions whose Stop input has no last_assistant_message. A
    message can span several lines with the same message id."""
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            f.seek(max(0, f.tell() - 2 * 1024 * 1024))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return ""
    msg_id, parts = None, []
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        msg = entry.get("message") if isinstance(entry, dict) else None
        if entry.get("type") != "assistant" or not isinstance(msg, dict):
            if msg_id and entry.get("type") == "user":
                break
            continue
        texts = [b.get("text", "") for b in msg.get("content") or []
                 if isinstance(b, dict) and b.get("type") == "text"]
        if msg_id is None:
            if not any(t.strip() for t in texts):
                continue
            msg_id = msg.get("id")
        elif msg.get("id") != msg_id:
            break
        parts[:0] = texts
    return "\n".join(t for t in parts if t.strip())


def last_reply(argv):
    """The agent's final reply for this turn, from whatever its hook passes:
    Claude Code's Stop input on stdin (last_assistant_message, else the
    transcript), or Codex's notify payload (an extra JSON argument)."""
    for raw in argv[1:]:
        try:
            payload = json.loads(raw)
        except ValueError:
            continue
        if isinstance(payload, dict) and isinstance(payload.get("last-assistant-message"), str):
            return payload["last-assistant-message"]
    data = _hook_stdin()
    if isinstance(data.get("last_assistant_message"), str):
        return data["last_assistant_message"]
    if isinstance(data.get("transcript_path"), str):
        return _last_reply_from_transcript(data["transcript_path"])
    return ""


def _is_codex_title(message):
    """Codex names a new thread with a side turn that answers {"title": "..."},
    and notify fires for it too, before the real turn has done anything. It is
    not the end of a turn: no message, no preview refresh, and it mustn't use up
    the event gap the real turn-done needs."""
    if not message.startswith("{"):
        return False
    try:
        data = json.loads(message)
    except ValueError:
        return False
    return isinstance(data, dict) and set(data) == {"title"} and isinstance(data["title"], str)


def cmd_event(argv):
    """Hook entry point. Never fails, never prints, never waits."""
    try:
        session = os.environ.get("ZELTRO_GUI_SESSION", "")
        # Codex appends its JSON payload as an extra argument; only the first counts
        # as the event.
        event = argv[0] if argv else ""
        if not session or event not in EVENTS or app_problem():
            return EXIT_OK
        message = last_reply(argv).strip() if event == "turn-done" else ""
        if _is_codex_title(message):
            return EXIT_OK
        ensure_dirs()
        stamp = os.path.join(GUI, ".last-%s-%s" % (re.sub(r"[^A-Za-z0-9_.-]", "_", session)[:80], event))
        try:
            if time.time() - os.stat(stamp).st_mtime < EVENT_GAP:
                return EXIT_OK
        except OSError:
            pass
        with open(stamp, "w"):
            pass
        args = {"event": event}
        if message:
            args["message"] = message[:MESSAGE_MAX]
        send_request("event", args)
    except Exception:  # noqa: BLE001 -- a hook must never fail the agent
        pass
    return EXIT_OK


ACTIONS = {"ask": cmd_ask, "secret": cmd_secret, "notify": cmd_notify,
           "open": cmd_open, "settings": cmd_settings, "preview": cmd_preview,
           "status": cmd_status, "screenshot": cmd_screenshot, "report": cmd_report,
           "event": cmd_event}


def main():
    argv = sys.argv[1:]
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(USAGE)
        return EXIT_OK if argv else EXIT_USAGE
    action, rest = argv[0], argv[1:]
    if action == "event":
        return cmd_event(rest)
    if action not in ACTIONS:
        print("zeltro gui: unknown action '%s'\n\n%s" % (action, USAGE), file=sys.stderr)
        return EXIT_USAGE
    if any(a in ("-h", "--help") for a in rest):
        print(USAGE)
        return EXIT_OK
    try:
        return ACTIONS[action](rest)
    except Usage as e:
        return finish(EXIT_USAGE, action, str(e))
    except NoApp as e:
        return finish(EXIT_NO_APP, action, str(e))


if __name__ == "__main__":
    sys.exit(main())
