#!/bin/bash

# Stack classification for `zeltro create`.
#
# Phase 1 of create: ask the AI ONLY which stack fits the user's idea, get a
# small JSON answer back, then let the user confirm with a menu. Zeltro itself
# then runs `zeltro new` / `zeltro install` — deterministically, with no AI
# involved in the actual creation.
#
# This exists because the old single-prompt approach made the agent hold the
# whole 100-app catalogue AND build the app in one context, and a wrong stack
# guess wasn't discovered until after a full build.
#
# Sourced by create.sh. Sets, on success:
#   CHOSEN_KIND  app|framework
#   CHOSEN_SLUG  installer slug or framework name
#   CHOSEN_DB    database engine (frameworks only; empty for apps)
#   CHOSEN_NAME  project directory / hostname
#   CHOSEN_CUSTOMIZE  yes|no — did the idea ask for work beyond the install
# Returns non-zero if classification failed, so the caller can fall back.

CATALOG_DIR="$DEV_DIR/catalog"

# Compact catalogue text for the prompt. Kept terse — this is paid for on every
# `zeltro create`.
_catalog_for_prompt() {
    python3 - "$CATALOG_DIR" << 'PYEOF'
import json, os, sys
d = sys.argv[1]
apps = json.load(open(os.path.join(d, "apps.json")))["apps"]
fws  = json.load(open(os.path.join(d, "frameworks.json")))["frameworks"]
print("READY-TO-RUN APPS, IN NO PARTICULAR ORDER OF PREFERENCE")
print("(installed via `zeltro install <slug>`; database is fixed by the installer):")
print(", ".join(a["slug"] for a in apps))
print()
print("FRAMEWORKS, IN NO PARTICULAR ORDER OF PREFERENCE")
print("(scaffolded via `zeltro new <slug> <name>`; the user writes the app).")
print("List order carries no meaning — judge each on fit alone:")
for f in fws:
    line = f"  {f['slug']} — {f['display']} ({f['runtime']}); databases: {', '.join(f['databases'])}"
    # The note carries what the model cannot know from the name alone — in-house
    # frameworks especially, which are absent from training data entirely.
    if f.get("note"):
        line += f"\n      {f['note']}"
    print(line)
PYEOF
}

# With ZELTRO_AI_LANGUAGE set, the user reads the "reason" sentences in that
# language. Everything the parser matches on stays English.
_classifier_language_line() {
    [[ -n "${AI_LANGUAGE:-}" ]] || return 0
    printf '\nWrite every "reason" in %s. Keep every JSON key, slug, and the values of\n"recommended" and "customization_requested" exactly as specified, in English.\n' "$AI_LANGUAGE"
}

_classifier_prompt() {
    local idea="$1"
    cat << PROMPTEOF
You are helping a user start a new project with Zeltro. Do NOT create anything.
Your only job is to decide which stack fits, and answer with JSON.

$(_catalog_for_prompt)

The user's idea:

$idea

Return BOTH of the following, always:

1. Exactly ONE framework — the best fit for building this custom, from scratch.
   This is never optional. Even when a ready-made app is the obvious answer,
   the user is entitled to see what building it themselves would look like.
2. Zero or more ready-to-run apps that genuinely fit, best first.
   Only include an app if it actually does what the user described. A
   vaguely-related app is worse than none: the user ends up fighting someone
   else's product instead of getting what they asked for. Returning an empty
   list is a perfectly good answer for anything bespoke.

3. A plain FOLDER, when the idea is not something people open in a browser: a
   script, a scraper, a command-line tool, a bot, a data clean-up, a set of
   documents. A folder project has no web server, database or address; the AI
   simply works in a folder on the user's computer. Give it a reason when it
   fits, otherwise return null for "folder". "A Python script that renames my
   photos by date" is a folder; "a website for my bakery" is not.

Also state which you would recommend overall — "app", "framework" or "folder".
An app is running in about two minutes; a framework build costs meaningfully
more time and AI tokens, but produces exactly what was asked for; a folder is
the right answer whenever nothing needs to be served on the web.

Also decide "customization_requested": does the idea ask for anything BEYOND
simply standing the software up? Configuring something, adding content, wiring
an integration, changing behaviour — that is true. "A git server", "a blog",
"set up Grafana" ask for nothing more than the install itself — that is false.
Judge only what the user actually wrote; do not invent extra work.

Give every option a "reason": one short sentence saying why it fits this
specific idea. The user sees these side by side and decides from them, so make
them concrete and comparative, not generic praise.
$(_classifier_language_line)
Recommend ONE database for the framework you chose, from that framework's
allowed list only, and say why in one short sentence. Judge it on the actual
workload the user described: sqlite for a small single-user or low-traffic tool
where a server is overkill, postgres for relational data, concurrency or
anything that will grow, mysql where the ecosystem expects it, mongodb only for
genuinely document-shaped data.
Suggest a short lowercase hyphenated project name, but ONLY when the idea
actually implies one. "track which guitar pedals are lent out" implies
"pedal-lending"; "a Django app for tracking chores" implies "chore-tracker".

Return null for project_name when the idea does not name a real subject —
"create a Flask project", "do a wordpress site", "a blog", "a website". Naming
it after the framework or app ("flask-app", "wordpress-site") or after nothing
in particular ("my-app", "new-project") is worse than returning null, because
the user will be asked directly instead.

Reply with ONLY this JSON. No prose, no markdown fences:

{
  "project_name": "short-hyphenated-name" | null,
  "recommended": "app" | "framework" | "folder",
  "customization_requested": true | false,
  "framework": {"slug": "<framework slug>", "reason": "<one short sentence, max 15 words>"},
  "apps": [
    {"slug": "<app slug>", "reason": "<one short sentence, max 15 words>"}
  ],
  "folder": {"reason": "<one short sentence, max 15 words>"} | null,
  "database": {"slug": "<engine>", "reason": "<one short sentence, max 15 words>"}
}
PROMPTEOF
}

# Pull JSON out of whatever the agent returned and validate every slug against
# the catalogue. Agents wrap JSON in prose or code fences often enough that
# naive parsing fails regularly; anything unrecognised is dropped rather than
# passed downstream where it would become a confusing `zeltro new` error.
# Takes the agent's reply as a FILE PATH, not on stdin: `python3 - <<EOF` reads
# the script itself from stdin, so a piped payload never reaches sys.stdin.
_parse_classification() {
    local raw_file="$1"
    python3 - "$CATALOG_DIR" "$raw_file" << 'PYEOF'
import json, os, re, sys

cat_dir = sys.argv[1]
raw = open(sys.argv[2], encoding="utf-8", errors="replace").read()

apps = {a["slug"]: a for a in json.load(open(os.path.join(cat_dir, "apps.json")))["apps"]}
fws  = {f["slug"]: f for f in json.load(open(os.path.join(cat_dir, "frameworks.json")))["frameworks"]}

# Strip fences, then take the outermost {...}
raw = re.sub(r"^\s*```[a-zA-Z]*\s*", "", raw.strip())
raw = re.sub(r"\s*```\s*$", "", raw)
start, end = raw.find("{"), raw.rfind("}")
if start == -1 or end == -1 or end <= start:
    sys.exit(1)
try:
    doc = json.loads(raw[start:end + 1])
except Exception:
    sys.exit(1)

# Apps first (ready immediately), framework last (always present as the
# build-it-yourself path). Unknown slugs are dropped rather than passed on.
out = []
for a in (doc.get("apps") or []):
    slug = (a.get("slug") or "").strip()
    why = (a.get("reason") or a.get("why") or "").strip().replace("\t", " ")[:120]
    if slug in apps:
        out.append(("app", slug, apps[slug]["display"], apps[slug]["database"], why))

fw = doc.get("framework") or {}
fw_slug = (fw.get("slug") or "").strip()
fw_why = (fw.get("reason") or fw.get("why") or "").strip().replace("\t", " ")[:120]
if fw_slug in fws:
    out.append(("framework", fw_slug, fws[fw_slug]["display"],
                ",".join(fws[fw_slug]["databases"]), fw_why))

# A plain folder project (no web server), when the model offers one.
_fo = doc.get("folder")
folder = None
if isinstance(_fo, dict):
    folder = ("folder", "folder", "Just a folder", "",
              (_fo.get("reason") or _fo.get("why") or "").strip().replace("\t", " ")[:120])

rec = (doc.get("recommended") or "").strip().lower()
if rec == "folder" and folder is None:
    folder = ("folder", "folder", "Just a folder", "", "")

if not out and folder is None:
    sys.exit(1)

# What the model would pick. Fall back to the framework when it named "app" but
# supplied none, which is the only way that answer can be self-contradictory.
has_app = any(o[0] == "app" for o in out)
has_fw = any(o[0] == "framework" for o in out)
if rec not in ("app", "framework", "folder"):
    rec = "app" if has_app else ("framework" if has_fw else "folder")
if rec == "app" and not has_app:
    rec = "framework" if has_fw else "folder"
if rec == "framework" and not has_fw:
    rec = "app" if has_app else "folder"

# The folder goes first when it's the recommendation, else last. Apps are capped
# so the folder and framework always survive the five-candidate limit.
apps_only = [o for o in out if o[0] == "app"][:3]
fw_only = [o for o in out if o[0] == "framework"]
if folder and rec == "folder":
    out = [folder] + apps_only + fw_only
else:
    out = apps_only + fw_only + ([folder] if folder else [])

# A name is only useful if it says something about the project. Reject the
# generic shapes outright rather than trusting the instruction above — the model
# still reaches for "flask-app" when the idea names no subject.
name = (doc.get("project_name") or "").strip().lower()
name = re.sub(r"[^a-z0-9-]+", "-", name).strip("-")[:40]

FILLER = {"my", "app", "apps", "site", "website", "project", "new", "web",
          "demo", "test", "thing", "tool", "system", "the", "a"}
known = set(apps) | set(fws)
if name:
    parts = [w for w in name.split("-") if w]
    meaningful = [w for w in parts if w not in FILLER and w not in known]
    # Nothing left once framework/app names and filler words are removed.
    if not meaningful:
        name = ""

# Preferred shape is a single {slug, reason}; the older bare array is still
# accepted so a stale reply doesn't fail the whole classification.
db_rec, db_reason = "", ""
_db = doc.get("database")
if isinstance(_db, dict):
    db_rec = (_db.get("slug") or "").strip().lower()
    db_reason = (_db.get("reason") or "").strip().replace("\t", " ")[:120]
elif isinstance(_db, str):
    db_rec = _db.strip().lower()
if not db_rec:
    _arr = [d for d in (doc.get("databases") or []) if isinstance(d, str)]
    db_rec = _arr[0].strip().lower() if _arr else ""

# TSV so bash can read it without another parser.
print("NAME\t" + name)
print("DBS\t" + db_rec)
print("DBWHY\t" + db_reason)
print("REC\t" + rec)
# Only an EXPLICIT false skips the build. A missing field must mean "yes":
# skipping wrongly drops half of what the user asked for, while running it
# needlessly only costs some tokens.
_cust = doc.get("customization_requested")
print("CUSTOM\t" + ("no" if _cust is False else "yes"))
for kind, slug, display, db, why in out[:5]:
    print(f"CAND\t{kind}\t{slug}\t{display}\t{db}\t{why}")
PYEOF
}

# Ask the agent, with one retry — a single malformed reply is common enough to
# be worth retrying, but two means something is genuinely wrong and the caller
# should fall back rather than loop.
#
# When it fails, the reason goes to $CLASSIFY_ERR_FILE (if set) as
# "<code><TAB><message>", so callers can show it rather than a generic line:
#   agent_failed  the agent itself errored (bad key, unsupported model, quota,
#                 not signed in...). Message: its last error line. Not retried.
#   no_stack      the agent answered, but not with a usable recommendation.
#
# Agents retry HTTP errors themselves (Codex reconnects five times, ~100s), so a
# watchdog stops the run as soon as the output shows a client error that a
# retry can't fix: 400, 401, 403 or 404.
_classify_fatal_re='unexpected status 40[0134]|API Error: 40[0134]|invalid_api_key|Incorrect API key|is not supported when using Codex|model_not_found|insufficient_quota'

_kill_tree() {
    local pid="$1" c
    for c in $(pgrep -P "$pid" 2>/dev/null); do _kill_tree "$c"; done
    kill "$pid" 2>/dev/null || true
}

# The most useful error line in an agent's output, cleaned up, or nothing.
_classify_error_line() {
    python3 - "$1" "$_classify_fatal_re" <<'PYEOF' 2>/dev/null
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
lines = [l.strip() for l in text.splitlines() if l.strip()]
fatal = re.compile(sys.argv[2], re.I)
generic = re.compile(r"error|unauthori[sz]ed|forbidden|denied|not supported|invalid|quota|rate limit|not found|failed|not signed in|log ?in|trusted directory", re.I)
pick = next((l for l in reversed(lines) if fatal.search(l)), None) \
    or next((l for l in reversed(lines) if generic.search(l) and "Reconnecting" not in l), None)
if pick:
    pick = re.sub(r"^(ERROR|Error|error)\s*:\s*", "", pick)
    pick = re.split(r",\s*(?:url|cf-ray|request id):", pick)[0]
    print(pick[:300])
PYEOF
}

_run_classifier() {
    local idea="$1" attempt parsed tmp pid rc fatal msg
    for attempt in 1 2; do
        tmp=$(mktemp)
        # Read-only question, no stdin: lets Codex answer outside a git repo.
        # The answer is parsed from stdout only: some agents (Codex) echo the
        # prompt, JSON template included, on stderr.
        ZELTRO_AI_READONLY=1 "$SCRIPT_DIR/ai.sh" --one-off "$(_classifier_prompt "$idea")" > "$tmp" 2> "$tmp.err" < /dev/null &
        pid=$!
        fatal=0
        while kill -0 "$pid" 2>/dev/null; do
            if grep -Eqi "$_classify_fatal_re" "$tmp" "$tmp.err" 2>/dev/null; then
                fatal=1; _kill_tree "$pid"; break
            fi
            sleep 1
        done
        rc=0; wait "$pid" 2>/dev/null || rc=$?
        parsed=$(_parse_classification "$tmp" 2>/dev/null) || parsed=""
        if [[ -n "$parsed" && "$fatal" == "0" ]]; then
            rm -f "$tmp" "$tmp.err"
            printf '%s' "$parsed"
            return 0
        fi
        cat "$tmp" >> "$tmp.err" 2>/dev/null
        msg="$(_classify_error_line "$tmp.err")"
        rm -f "$tmp" "$tmp.err"
        if [[ "$fatal" == "1" || ( "$rc" != "0" && -n "$msg" ) ]]; then
            if [[ -n "${CLASSIFY_ERR_FILE:-}" ]]; then
                printf 'agent_failed\t%s: %s\n' "$(zeltro_agent_display_name "${AI_AGENT:-agent}")" "${msg:-the AI agent exited with an error}" > "$CLASSIFY_ERR_FILE"
            fi
            return 1
        fi
        [[ $attempt -eq 1 ]] && echo-yellow "Could not read the AI's stack recommendation; retrying once ..." >&2
    done
    [[ -n "${CLASSIFY_ERR_FILE:-}" ]] && printf 'no_stack\t%s\n' "could not determine a stack from that description" > "$CLASSIFY_ERR_FILE"
    return 1
}

# Splits the last failure into CLASSIFY_ERR_CODE and CLASSIFY_ERR_MESSAGE.
_classify_last_error() {
    local line=""
    [[ -n "${CLASSIFY_ERR_FILE:-}" && -s "$CLASSIFY_ERR_FILE" ]] && IFS= read -r line < "$CLASSIFY_ERR_FILE"
    [[ -n "$line" ]] || line="$(printf 'no_stack\tcould not determine a stack from that description')"
    CLASSIFY_ERR_CODE="${line%%$'\t'*}"
    CLASSIFY_ERR_MESSAGE="${line#*$'\t'}"
}

# Numbered, coloured menu. Plain text rather than whiptail/dialog so it works
# identically on Linux and macOS with no extra dependency, and matches the
# picker `zeltro new` already uses.
# Args: prompt, default index, then "label|hint" entries.
_menu_choose() {
    local title="$1" default="$2"; shift 2
    local -a entries=("$@")
    local i=1 choice

    echo-return
    echo-cyan "$title"
    echo-return
    for e in "${entries[@]}"; do
        local label="${e%%|*}" hint="${e#*|}"
        printf "  \033[1;33m%d)\033[0m %s" "$i" "$label" >&2
        [[ -n "$hint" && "$hint" != "$label" ]] && printf "  \033[2m— %s\033[0m" "$hint" >&2
        printf "\n" >&2
        i=$((i + 1))
    done
    echo-return
    echo-yellow -ne "Enter choice [$default] > "
    read choice || choice=""
    echo-return
    [[ -z "$choice" ]] && choice="$default"
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#entries[@]} )); then
        echo-yellow "Invalid choice — using $default."
        choice="$default"
    fi
    printf '%s' "$choice"
}

# Orchestrates phase 1. Falls back to caller on failure.
classify_project() {
    local idea="$1"
    local non_interactive="$2"   # 1 = pick the top recommendation silently

    echo-return
    echo-cyan "Working out which stack fits ..."

    local parsed
    CLASSIFY_ERR_FILE="${CLASSIFY_ERR_FILE:-$(mktemp)}"
    parsed=$(_run_classifier "$idea") || return 1

    local suggested_name suggested_dbs
    suggested_name=$(printf '%s' "$parsed" | awk -F'\t' '$1=="NAME"{print $2; exit}')
    suggested_dbs=$(printf '%s' "$parsed" | awk -F'\t' '$1=="DBS"{print $2; exit}')
    local suggested_db_why
    suggested_db_why=$(printf '%s' "$parsed" | awk -F'\t' '$1=="DBWHY"{print $2; exit}')
    local recommended_kind
    recommended_kind=$(printf '%s' "$parsed" | awk -F'\t' '$1=="REC"{print $2; exit}')
    CHOSEN_CUSTOMIZE=$(printf '%s' "$parsed" | awk -F'\t' '$1=="CUSTOM"{print $2; exit}')
    [[ -z "$CHOSEN_CUSTOMIZE" ]] && CHOSEN_CUSTOMIZE="yes"

    local -a kinds slugs displays dbs whys labels
    while IFS=$'\t' read -r tag kind slug display db why; do
        [[ "$tag" != "CAND" ]] && continue
        kinds+=("$kind"); slugs+=("$slug"); displays+=("$display"); dbs+=("$db"); whys+=("$why")
    done < <(printf '%s\n' "$parsed")

    [[ ${#slugs[@]} -eq 0 ]] && return 1

    local idx=1
    if [[ "$non_interactive" == "1" ]]; then
        local n
        for n in "${!slugs[@]}"; do
            if [[ "${kinds[$n]}" == "${recommended_kind}" ]]; then idx=$((n + 1)); break; fi
        done
    else
        # Apps come first (running in ~2 minutes), the framework last (does
        # exactly what was asked, but costs real time and tokens). Mark whichever
        # the model actually recommends rather than always the first row, so the
        # marker means something.
        local n tag rec_n=-1
        for n in "${!slugs[@]}"; do
            if [[ "${kinds[$n]}" == "${recommended_kind}" ]]; then rec_n=$n; break; fi
        done
        for n in "${!slugs[@]}"; do
            if [[ "${kinds[$n]}" == "app" ]]; then
                tag="ready to run — live in about 2 minutes"
            elif [[ "${kinds[$n]}" == "folder" ]]; then
                tag="no web server — your AI works in a plain folder"
            else
                tag="custom build — exactly what you asked for, more time and tokens"
            fi
            if [[ $n -eq $rec_n ]]; then
                labels+=("$(printf '%s  \033[2m(%s)\033[0m  \033[1;32m(Recommended)\033[0m' "${displays[$n]}" "$tag")|${whys[$n]}")
            else
                labels+=("$(printf '%s  \033[2m(%s)\033[0m' "${displays[$n]}" "$tag")|${whys[$n]}")
            fi
        done
        # No "just choose for me" entry: pressing Enter already takes the
        # recommendation, so it only added a row that did nothing new. A dev who
        # dislikes every option can create the project by hand instead.
        local default_idx=$(( rec_n >= 0 ? rec_n + 1 : 1 ))
        idx=$(_menu_choose "How would you like to build this?" "$default_idx" "${labels[@]}")
    fi

    local sel=$((idx - 1))
    CHOSEN_KIND="${kinds[$sel]}"
    CHOSEN_SLUG="${slugs[$sel]}"
    CHOSEN_DB=""

    if [[ "$CHOSEN_KIND" == "folder" ]]; then
        # No database, container or address to choose.
        :
    elif [[ "$CHOSEN_KIND" == "app" ]]; then
        # The installer's compose fixes the engine, so there is nothing to ask.
        local appdb="${dbs[$sel]}"
        if [[ -n "$appdb" ]]; then
            echo-white "Database: $appdb (set by the ${displays[$sel]} installer)"
        else
            echo-white "Database: managed internally by ${displays[$sel]}"
        fi
    else
        # Offer only engines this framework actually works with, recommended first.
        local -a allowed recommended ordered
        IFS=',' read -r -a allowed <<< "${dbs[$sel]}"
        IFS=',' read -r -a recommended <<< "$suggested_dbs"
        local d r
        for r in "${recommended[@]}"; do
            for d in "${allowed[@]}"; do
                [[ "$r" == "$d" ]] && ordered+=("$r")
            done
        done
        for d in "${allowed[@]}"; do
            local seen=0 o
            for o in "${ordered[@]}"; do [[ "$o" == "$d" ]] && seen=1; done
            [[ $seen -eq 0 ]] && ordered+=("$d")
        done

        if [[ "$non_interactive" == "1" || ${#ordered[@]} -eq 1 ]]; then
            CHOSEN_DB="${ordered[0]}"
            [[ ${#ordered[@]} -eq 1 ]] && echo-white "Database: ${ordered[0]} (only engine ${displays[$sel]} supports)"
        else
            local -a dblabels
            local first=1 o
            for o in "${ordered[@]}"; do
                if [[ $first -eq 1 ]]; then
                    dblabels+=("$(printf '%s  \033[1;32m(Recommended)\033[0m' "$o")|${suggested_db_why:-best fit for this workload}")
                    first=0
                else
                    dblabels+=("$o|")
                fi
            done
            local dbidx
            dbidx=$(_menu_choose "Which database for ${displays[$sel]}?" 1 "${dblabels[@]}")
            CHOSEN_DB="${ordered[$((dbidx - 1))]}"
        fi
    fi

    CHOSEN_NAME="$suggested_name"
    local typed
    if [[ "$non_interactive" != "1" ]]; then
        if [[ -n "$CHOSEN_NAME" ]]; then
            echo-return
            echo-yellow -ne "Project name [$CHOSEN_NAME] > "
            read typed || typed=""
            echo-return
        else
            # The idea named no real subject, so there is nothing sensible to
            # default to. Ask rather than inventing "flask-app".
            echo-return
            echo-white "Your description doesn't suggest a project name."
            while [[ -z "$CHOSEN_NAME" ]]; do
                echo-yellow -ne "What should this project be called? > "
                read typed || typed=""
                typed=$(echo "$typed" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]\+/-/g; s/^-//; s/-$//')
                [[ -n "$typed" ]] && CHOSEN_NAME="$typed"
            done
            echo-return
            typed=""
        fi
        [[ -n "$typed" ]] && CHOSEN_NAME=$(echo "$typed" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]\+/-/g; s/^-//; s/-$//')
    fi

    # Scripted runs cannot be asked, so fall back to the chosen slug — which is
    # also what `zeltro install <app>` would have named it — and say so.
    if [[ -z "$CHOSEN_NAME" ]]; then
        CHOSEN_NAME="$CHOSEN_SLUG"
        echo-yellow "No project name could be derived from the idea — using '$CHOSEN_NAME'." >&2
    fi

    return 0
}

# Phase 1 on its own: classify an idea and print the result without touching the
# menus and without creating anything. Exists for GUI/API consumers that need to
# render the choices as native UI.
#
# This is deliberately NOT the same as the non-interactive path used by
# --one-off/--json-output: that one silently takes the top recommendation, which
# throws away the user's choice, and the choice is the entire point of the menus.
#
# Args: idea, want_json (1 = JSON, anything else = human-readable).
classify_only() {
    local idea="$1" want_json="$2"
    local parsed

    CLASSIFY_ERR_FILE="${CLASSIFY_ERR_FILE:-$(mktemp)}"
    if ! parsed=$(_run_classifier "$idea"); then
        _classify_last_error
        rm -f "$CLASSIFY_ERR_FILE"
        if [[ "$want_json" == "1" ]]; then
            python3 -c 'import json,sys; print(json.dumps({"action":"classify","status":"error","error":sys.argv[1],"message":sys.argv[2]}))' "$CLASSIFY_ERR_CODE" "$CLASSIFY_ERR_MESSAGE"
        else
            echo-red "$CLASSIFY_ERR_MESSAGE"
        fi
        return 1
    fi
    rm -f "$CLASSIFY_ERR_FILE"

    if [[ "$want_json" == "1" ]]; then
        printf '%s' "$parsed" | python3 -c '
import json, sys

name = rec = db_slug = db_why = ""
cust = "yes"
cands = []

for line in sys.stdin.read().split("\n"):
    if not line:
        continue
    f = line.split("\t")
    tag = f[0]
    val = f[1] if len(f) > 1 else ""
    if   tag == "NAME":   name = val
    elif tag == "DBS":    db_slug = val
    elif tag == "DBWHY":  db_why = val
    elif tag == "REC":    rec = val
    elif tag == "CUSTOM": cust = val
    elif tag == "CAND" and len(f) >= 6:
        kind, slug, display, db, why = f[1], f[2], f[3], f[4], f[5]
        c = {"kind": kind, "slug": slug, "display": display, "reason": why}
        # Apps have their database fixed by the installer; frameworks offer a
        # constrained set. The consumer must not present a choice for an app.
        if kind == "framework":
            c["databases"] = [d for d in db.split(",") if d]
        elif kind == "app":
            c["database"] = db
        # kind "folder": a plain folder project, no database or address.
        cands.append(c)

print(json.dumps({
    "action": "classify",
    "status": "success",
    "project_name": name or None,
    "recommended": rec,
    "customization_requested": cust != "no",
    "database": ({"slug": db_slug, "reason": db_why} if db_slug else None),
    "candidates": cands,
}))
'
        return 0
    fi

    # Human-readable form, so the flag is useful from a terminal too.
    local name rec_kind db_slug db_why
    name=$(printf '%s' "$parsed"   | awk -F'\t' '$1=="NAME"{print $2; exit}')
    rec_kind=$(printf '%s' "$parsed" | awk -F'\t' '$1=="REC"{print $2; exit}')
    db_slug=$(printf '%s' "$parsed"  | awk -F'\t' '$1=="DBS"{print $2; exit}')
    db_why=$(printf '%s' "$parsed"   | awk -F'\t' '$1=="DBWHY"{print $2; exit}')

    echo-return
    echo-cyan "Classification"
    echo-white "  Project name: ${name:-<none suggested — ask the user>}"
    echo-white "  Recommended:  ${rec_kind}"
    [[ -n "$db_slug" ]] && echo-white "  Database:     ${db_slug}${db_why:+ — $db_why}"
    echo-return
    echo-cyan "Candidates"
    while IFS=$'\t' read -r tag kind slug display db why; do
        [[ "$tag" != "CAND" ]] && continue
        if [[ "$kind" == "framework" ]]; then
            echo-white "  [framework] $display ($slug) — databases: ${db//,/, }"
        elif [[ "$kind" == "folder" ]]; then
            echo-white "  [folder]    $display (no web server, database or address)"
        else
            echo-white "  [app]       $display ($slug)${db:+ — database: $db}"
        fi
        [[ -n "$why" ]] && echo-white "              $why"
    done < <(printf '%s\n' "$parsed")
    echo-return
    return 0
}
