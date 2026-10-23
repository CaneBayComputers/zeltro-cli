#!/usr/bin/env python3
"""Agent sign-in for Zeltro: what each agent CLI can sign in with, whether it is
signed in on this machine, and running its sign-in for an app that has no
terminal to give it.

    ai_auth.py capabilities                      JSON: per-agent sign-in options
    ai_auth.py status --agent A [--json-output]  installed / version / signed in
    ai_auth.py login  --agent A [--json-output] [--local-browser] [--force]

Reached as `zeltro ai-status` and `zeltro ai-login`. The per-agent knowledge
lives here so the app behaves the same on local, WSL and SSH hosts.

login with --json-output prints one JSON object per line as it goes:

    {"event":"open","url":"...","code":"ABCD-EFGH"}   device code flows (codex)
    {"event":"open","url":"..."}                      a link to open
    {"event":"need_code"}                             write the pasted code + "\\n" to stdin
    {"event":"done","signed_in":true,"account":"..."}
    {"event":"error","message":"..."}

status --json-output: {"installed","version","auth","signed_in","account",
"subscription","api_key","endpoint","login_supported"}. auth is "subscription",
"api_key", "endpoint", "none" or "unknown" (a key-only agent with no key here).

Claude Code (2.1.309) prints a link whose sign-in page shows a code to paste
back ("Paste code here if prompted >"), and hands the browser a second link that
redirects to a localhost port the waiting process listens on. The pasted-code
link works wherever the browser is; the localhost one only when the browser runs
on the same machine, so it's used only with --local-browser. Both links belong
to the process that printed them. Codex (0.128) does a device code flow: a fixed
URL plus a one-time code, and the process finishes by itself once it's entered.

Never prints a token or key.
"""
import base64
import json
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

# Which sign-ins each agent supports (2026-10-23). Subscription sign-in: Claude
# Code with Claude Pro/Max; Codex with ChatGPT; OpenCode with ChatGPT only
# (Anthropic forbids Claude Pro/Max sign-ins in third-party tools); Hermes with
# Nous Portal or ChatGPT. Gemini CLI lost Google sign-in for individuals on
# 2026-06-18 and Qwen Code's free sign-in closed 2026-04-15; aider never had one.
# "endpoint" is the API format a custom endpoint (base URL + key + model) must
# speak for that agent, or None. Most servers (OpenRouter, Ollama, LM Studio,
# vLLM, DeepSeek) speak "openai" (chat completions). Codex 0.128 only speaks
# OpenAI's Responses API ("openai-responses"): OpenRouter, Ollama and LM Studio
# offer it, others need a gateway such as LiteLLM. Claude Code takes Anthropic's
# Messages format (DeepSeek, Kimi, GLM and LiteLLM offer one), Gemini CLI only
# Google's.
CAPABILITIES = {
    "claude":   {"subscription": True,  "api_key": True, "endpoint": "anthropic"},
    "codex":    {"subscription": True,  "api_key": True, "endpoint": "openai-responses"},
    "gemini":   {"subscription": False, "api_key": True, "endpoint": "gemini"},
    "qwen":     {"subscription": False, "api_key": True, "endpoint": "openai"},
    "aider":    {"subscription": False, "api_key": True, "endpoint": "openai"},
    "opencode": {"subscription": True,  "api_key": True, "endpoint": "openai",
                 "subscription_note": "ChatGPT only"},
    "hermes":   {"subscription": True,  "api_key": True, "endpoint": "openai",
                 "subscription_note": "Nous Portal or ChatGPT"},
}
# Agents whose sign-in `ai-login` can run.
LOGIN_SUPPORTED = ["claude", "codex"]

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07|\r")
LOGIN_TIMEOUT = 900


def run(cmd, timeout=15, env=None):
    """(exit code, stdout+stderr) of cmd; (None, "") if it can't run."""
    try:
        p = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=timeout, env=env)
        return p.returncode, ANSI.sub("", p.stdout.decode("utf-8", "replace"))
    except (OSError, subprocess.TimeoutExpired):
        return None, ""


def which(cmd):
    """shutil.which, skipping Windows binaries that WSL puts on PATH (/mnt/c/...)."""
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if re.match(r"/mnt/[a-zA-Z]/", d + "/"):
            continue
        p = shutil.which(cmd, path=d) if d else None
        if p:
            return p
    return None


def installed(agent):
    if not which(agent):
        return False
    if agent == "hermes":
        # Meta's Hermes JavaScript engine installs a "hermes" binary too.
        rc, out = run(["hermes", "--version"])
        return rc == 0 and "Hermes Agent" in out
    return True


def version(agent):
    rc, out = run([agent, "--version"])
    if rc != 0 or not out.strip():
        return ""
    m = re.search(r"\d+\.\d+[\w.+-]*", out)
    return m.group(0) if m else out.strip().splitlines()[0][:60]


def jwt_claims(token):
    try:
        part = token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
    except Exception:
        return {}


def status_claude():
    rc, out = run(["claude", "auth", "status", "--json"])
    try:
        d = json.loads(out[out.index("{"):])
    except ValueError:
        return {"auth": "unknown", "signed_in": False, "account": ""}
    if not d.get("loggedIn"):
        return {"auth": "none", "signed_in": False, "account": ""}
    method = d.get("authMethod") or ""
    auth = "subscription" if method == "claude.ai" else ("api_key" if method else "unknown")
    account = d.get("email") or ""
    if d.get("subscriptionType"):
        account = (account + " (" + d["subscriptionType"] + ")").strip()
    return {"auth": auth, "signed_in": True, "account": account}


def status_codex():
    rc, out = run(["codex", "login", "status"])
    if rc is None:
        return {"auth": "unknown", "signed_in": False, "account": ""}
    if rc != 0 or "not logged in" in out.lower():
        return {"auth": "none", "signed_in": False, "account": ""}
    if "chatgpt" in out.lower():
        account = ""
        home = os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")
        try:
            tokens = json.load(open(os.path.join(home, "auth.json"))).get("tokens") or {}
            claims = jwt_claims(tokens.get("id_token") or "")
            account = claims.get("email") or ""
            plan = (claims.get("https://api.openai.com/auth") or {}).get("chatgpt_plan_type")
            if plan:
                account = (account + " (" + plan + ")").strip()
        except Exception:
            pass
        return {"auth": "subscription", "signed_in": True, "account": account}
    if "api key" in out.lower():
        return {"auth": "api_key", "signed_in": True, "account": ""}
    return {"auth": "unknown", "signed_in": True, "account": ""}


def status_opencode():
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    try:
        creds = json.load(open(os.path.join(base, "opencode", "auth.json")))
    except Exception:
        creds = {}
    if (creds.get("openai") or {}).get("type") == "oauth":
        return {"auth": "subscription", "signed_in": True, "account": "ChatGPT"}
    if any((v or {}).get("type") == "api" for v in creds.values()):
        return {"auth": "api_key", "signed_in": True, "account": ""}
    return {"auth": "none", "signed_in": False, "account": ""}


def status_hermes():
    for provider, label in (("nous", "Nous Portal"), ("openai-codex", "ChatGPT")):
        rc, out = run(["hermes", "auth", "status", provider], timeout=20)
        if rc == 0 and re.search(r":\s*logged in", out, re.I):
            return {"auth": "subscription", "signed_in": True, "account": label}
    return {"auth": "unknown", "signed_in": False, "account": ""}


STATUS = {"claude": status_claude, "codex": status_codex,
          "opencode": status_opencode, "hermes": status_hermes}


def status(agent):
    out = {"action": "ai_status", "agent": agent, "installed": installed(agent),
           "version": "", "auth": "none", "signed_in": False, "account": ""}
    out.update({k: v for k, v in CAPABILITIES[agent].items()})
    out["login_supported"] = agent in LOGIN_SUPPORTED
    if not out["installed"]:
        return out
    out["version"] = version(agent)
    # A profile with its own key or endpoint runs on that, not on a sign-in, so
    # it counts as ready. `zeltro ai-status` passes what the run would use
    # (ZELTRO_AI_* overrides, else the .env) in ZELTRO_PROFILE_*.
    if os.environ.get("ZELTRO_PROFILE_AGENT") == agent:
        if os.environ.get("ZELTRO_PROFILE_HAS_BASE") == "1":
            out.update(auth="endpoint", signed_in=True)
            return out
        if os.environ.get("ZELTRO_PROFILE_HAS_KEY") == "1":
            out.update(auth="api_key", signed_in=True)
            return out
    if agent in STATUS:
        out.update(STATUS[agent]())
    else:
        # Key-only agents: the key comes with the profile at run time, so there
        # is nothing stored here to check.
        out["auth"] = "unknown"
    return out


# --- login --------------------------------------------------------------------

class Login:
    def __init__(self, agent, as_json, local_browser):
        self.agent, self.as_json, self.local_browser = agent, as_json, local_browser
        self.proc = None
        self.buf = ""
        self.lock = threading.Lock()
        self.tmp = tempfile.mkdtemp(prefix="zeltro-login-")

    def emit(self, event, **fields):
        if self.as_json:
            print(json.dumps(dict(event=event, **fields)), flush=True)
            return
        if event == "open":
            print("Open this link to sign in:\n  " + fields["url"], flush=True)
            if fields.get("code"):
                print("Then enter this code: " + fields["code"], flush=True)
        elif event == "need_code":
            print("Paste the code the sign-in page shows you, then press Enter:", flush=True)
        elif event == "done":
            print("Signed in" + (" as " + fields["account"] if fields.get("account") else "") + ".", flush=True)
        elif event == "error":
            print("Sign-in failed: " + fields["message"], file=sys.stderr, flush=True)

    def kill(self):
        """End the sign-in process and anything it started. A login that stays
        behind keeps its localhost port and its link alive."""
        if not self.proc or self.proc.poll() is not None:
            return
        for sig, wait in ((signal.SIGTERM, 3), (signal.SIGKILL, 1)):
            try:
                os.killpg(self.proc.pid, sig)
            except OSError:
                return
            try:
                self.proc.wait(wait)
                return
            except subprocess.TimeoutExpired:
                pass

    def stop(self, *_):
        self.kill()
        shutil.rmtree(self.tmp, ignore_errors=True)
        sys.exit(130)

    def start(self, cmd, env, stdin_pipe):
        self.proc = subprocess.Popen(
            cmd, env=env, start_new_session=True,
            stdin=subprocess.PIPE if stdin_pipe else subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

        def pump():
            fd = self.proc.stdout.fileno()
            while True:
                chunk = os.read(fd, 4096)
                if not chunk:
                    break
                with self.lock:
                    self.buf += ANSI.sub("", chunk.decode("utf-8", "replace"))
        threading.Thread(target=pump, daemon=True).start()

    def text(self):
        with self.lock:
            return self.buf

    def wait_for(self, pattern, deadline):
        """The first match of pattern in the output, or None once the process
        exits or the deadline passes."""
        while time.time() < deadline:
            m = re.search(pattern, self.text())
            if m:
                return m
            if self.proc.poll() is not None:
                time.sleep(0.2)
                return re.search(pattern, self.text())
            time.sleep(0.1)
        return None

    def last_line(self):
        """The sign-in's last error, readable. Claude prints its paste prompt
        without a newline, so the error after a code lands on the same line."""
        lines = [re.sub(r"^.*?Paste code here if prompted >\s*", "", l).strip() for l in self.text().splitlines()]
        lines = [l for l in lines if l]
        useful = [l for l in lines if re.search(r"error|fail|invalid|denied|expired|timed out", l, re.I)]
        line = (useful or lines or ["the sign-in process exited"])[-1][:300]
        # Claude 2.1.309 exits on a well-formed but wrong code with "Login
        # failed: Request failed with status code 400".
        if self.agent == "claude" and re.search(r"status code 400|invalid_grant", line):
            return "That code wasn't accepted. Start the sign-in again and copy the whole code from the sign-in page."
        return line

    def finish(self, deadline):
        while self.proc.poll() is None and time.time() < deadline:
            time.sleep(0.2)
        if self.proc.poll() is None:
            self.kill()
            self.emit("error", message="Timed out waiting for the sign-in to finish.")
            return 1
        st = status(self.agent)
        if st["signed_in"]:
            self.emit("done", signed_in=True, account=st["account"], auth=st["auth"])
            return 0
        self.emit("error", message=self.last_line())
        return 1

    def claude(self, deadline):
        env = dict(os.environ)
        url_file = os.path.join(self.tmp, "url")
        browser = os.path.join(self.tmp, "browser")
        with open(browser, "w") as f:
            # Records the link Claude hands a browser instead of opening one: on
            # a remote host there is no browser, and locally the app opens it.
            f.write('#!/bin/sh\nprintf "%%s" "$1" > "%s"\n' % url_file)
        os.chmod(browser, 0o700)
        env["BROWSER"] = browser
        # stdin stays a pipe in both modes: the pasted code goes there, and EOF
        # on it would end a localhost-callback login still waiting for the browser.
        self.start(["claude", "auth", "login"], env, stdin_pipe=True)

        if self.local_browser:
            while time.time() < deadline and self.proc.poll() is None:
                if os.path.exists(url_file) and os.path.getsize(url_file):
                    break
                time.sleep(0.1)
            if os.path.exists(url_file) and os.path.getsize(url_file):
                self.emit("open", url=open(url_file).read().strip())
                return self.finish(deadline)
            # No browser link came: fall back to the printed one.

        m = self.wait_for(r"visit:\s*(https://\S+)", deadline)
        if not m:
            self.kill()
            self.emit("error", message="Claude Code didn't print a sign-in link: " + self.last_line())
            return 1
        self.emit("open", url=m.group(1))

        # A wrong code prints "Invalid code. Please make sure the full code was
        # copied." and Claude keeps reading stdin for another, without a new prompt.
        prompts = 0
        while time.time() < deadline and self.proc.poll() is None:
            t = self.text()
            n = t.count("Paste code here") + t.count("Invalid code")
            if n > prompts:
                prompts = n
                retry = {"retry": True, "message": "That code wasn't accepted. Copy the whole code and try again."} if prompts > 1 else {}
                self.emit("need_code", **retry)
                code = self.read_code(deadline)
                if code is None:
                    break
                try:
                    self.proc.stdin.write((code + "\n").encode())
                    self.proc.stdin.flush()
                except OSError:
                    break
            time.sleep(0.2)
        return self.finish(deadline)

    def read_code(self, deadline):
        """A line from our stdin, or None on EOF or the deadline."""
        while time.time() < deadline:
            if self.proc.poll() is not None:
                return None
            r, _, _ = select.select([sys.stdin], [], [], 0.5)
            if r:
                line = sys.stdin.readline()
                if not line:
                    return None
                if line.strip():
                    return line.strip()
        return None

    def codex(self, deadline):
        self.start(["codex", "login", "--device-auth"], dict(os.environ), stdin_pipe=False)
        url = self.wait_for(r"(https://auth\.openai\.com/\S+)", deadline)
        code = self.wait_for(r"\b([A-Z0-9]{4,5}-[A-Z0-9]{4,6})\b", min(deadline, time.time() + 30))
        if not url or not code:
            self.kill()
            self.emit("error", message="Codex didn't print a sign-in link and code: " + self.last_line())
            return 1
        self.emit("open", url=url.group(1), code=code.group(1))
        return self.finish(deadline)


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    cmd, args = argv[0], argv[1:]
    as_json = os.environ.get("JSON_OUTPUT") == "1"
    agent, local_browser, force, timeout = "", False, False, LOGIN_TIMEOUT
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--json-output", "--json"):
            as_json = True
        elif a == "--agent" and i + 1 < len(args):
            agent = args[i + 1]; i += 1
        elif a == "--local-browser":
            local_browser = True
        elif a == "--force":
            force = True
        elif a == "--timeout" and i + 1 < len(args) and args[i + 1].isdigit():
            timeout = int(args[i + 1]); i += 1
        elif a in ("-h", "--help"):
            print(__doc__.strip())
            return 0
        else:
            return fail(cmd, as_json, "Unknown option: " + a)
        i += 1

    if cmd == "capabilities":
        print(json.dumps({"agents": CAPABILITIES, "login_supported": LOGIN_SUPPORTED}))
        return 0
    if cmd not in ("status", "login"):
        return fail(cmd, as_json, "Unknown command: " + cmd)
    if agent not in CAPABILITIES:
        return fail(cmd, as_json, "--agent must be one of: " + ", ".join(CAPABILITIES))

    if cmd == "status":
        st = status(agent)
        if as_json:
            print(json.dumps(st))
        else:
            if not st["installed"]:
                print(agent + ": not installed")
            else:
                who = {"subscription": "signed in with a subscription", "api_key": "signed in with an API key",
                       "endpoint": "uses a custom endpoint",
                       "none": "not signed in", "unknown": "sign-in unknown (uses the profile's API key)"}[st["auth"]]
                print("%s %s: %s%s" % (agent, st["version"], who, (" (" + st["account"] + ")") if st["account"] else ""))
        return 0

    login = Login(agent, as_json, local_browser)
    for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(s, login.stop)
    try:
        if not installed(agent):
            login.emit("error", message=agent + " is not installed. Install it with: zeltro ai-install --agent " + agent)
            return 1
        if agent not in LOGIN_SUPPORTED:
            login.emit("error", message="not supported yet")
            return 1
        if not force:
            st = status(agent)
            if st["signed_in"] and st["auth"] == "subscription":
                login.emit("done", signed_in=True, account=st["account"], auth=st["auth"], already=True)
                return 0
        deadline = time.time() + timeout
        return getattr(login, agent)(deadline)
    finally:
        shutil.rmtree(login.tmp, ignore_errors=True)


def fail(cmd, as_json, message):
    if as_json:
        key = "event" if cmd == "login" else "status"
        print(json.dumps({key: "error", "message": message} if cmd == "login"
                         else {"action": "ai_" + cmd, "status": "error", "message": message}))
    else:
        print(message, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
