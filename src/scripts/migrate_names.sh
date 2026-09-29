#!/bin/bash

# zeltro migrate-names: move a machine installed under the old "Podium" name onto
# the zeltro-* names.
#
# Such a machine runs COMPOSE_PROJECT_NAME=podium-cli, so its shared containers
# are podium-mariadb, podium-postgres, ..., its network is podium-cli_vpc and its
# data lives in podium-cli_* volumes, and every project names those hosts in its
# compose file, .env and config. Nothing can simply be renamed: Docker has no
# volume rename, and a container's network is fixed when it is created.
#
# What --yes does, in order (the default is a preview that changes nothing):
#   1. back up /etc/zeltro-cli/.env and every project file it will rewrite
#   2. stop every project and the shared services (containers and the network are
#      removed; volumes are not)
#   3. copy each podium-cli_* volume into a new zeltro-cli_* volume and verify the
#      copy (names, sizes and modes of every file). The old volumes are KEPT.
#   4. switch the .env to COMPOSE_PROJECT_NAME=zeltro-cli and zeltro-* names
#   5. rewrite the exact service hostnames and the network name in project files
#   6. start the shared services under the new names, check the databases match,
#      and start the projects that were running
# --rollback DIR undoes it from that backup onto the old volumes. Anything written
# to the new volumes after the migration is lost by a rollback.
# --remove-old-volumes deletes the podium-cli_* volumes once you're satisfied.

set -e

ORIG_DIR=$(pwd)
cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..
DEV_DIR=$(pwd)
source scripts/pre_check.sh
SCRIPT_DIR="$DEV_DIR/scripts"
ZELTRO_BIN="$DEV_DIR/zeltro"

ENV_FILE="/etc/zeltro-cli/.env"
OLD_PREFIX="podium"; NEW_PREFIX="zeltro"
OLD_PROJECT="podium-cli"; NEW_PROJECT="zeltro-cli"
# Every shared service's container name, as the .env key's stem and the name suffix.
SERVICES="MARIADB:mariadb REDIS:redis MEMCACHED:memcached MONGO:mongo POSTGRES:postgres PHPMYADMIN:phpmyadmin MAILHOG:mailhog ADMINER:adminer MEILISEARCH:meilisearch MINIO:minio MONGOEXPRESS:mongo-express REDISINSIGHT:redisinsight"

MODE="preview"; ROLLBACK_DIR=""
usage() {
    echo-white "Usage: zeltro migrate-names [--yes | --rollback DIR | --remove-old-volumes]"
    echo-white ""
    echo-white "Move a machine installed under the old Podium name (podium-* containers,"
    echo-white "podium-cli_vpc) onto the zeltro-* names, keeping every database's data."
    echo-white ""
    echo-white "  (no option)            Preview: show what would change. Changes nothing."
    echo-white "  --yes                  Do it. Stops all projects and the shared services while it runs."
    echo-white "  --rollback DIR         Undo a migration from its backup directory (printed by --yes)."
    echo-white "  --remove-old-volumes   Delete the old podium-cli_* volumes after a successful migration."
    echo-white "  --projects-only        Only rewrite project files (podium-* hosts and podium-cli_vpc -> zeltro-*),"
    echo-white "                         e.g. after reinstalling Zeltro fresh instead of migrating. No Docker changes."
}
while [ $# -gt 0 ]; do
    case "$1" in
        --yes) MODE="run"; shift ;;
        --rollback) MODE="rollback"; ROLLBACK_DIR="${2:-}"; [ -n "$ROLLBACK_DIR" ] || error "--rollback needs the backup directory"; shift 2 ;;
        --remove-old-volumes) MODE="remove-old"; shift ;;
        --projects-only) MODE="projects-only"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) error "Unknown option: $1 (see --help)" ;;
    esac
done

[ -f "$ENV_FILE" ] || error "$ENV_FILE not found. Is Zeltro configured on this machine?"
docker info >/dev/null 2>&1 || error "Docker isn't reachable."

env_get() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | sed 's/^"//; s/"$//'; }
as_root_if_needed() { if [ -w "$1" ]; then shift; "$@"; else shift; sudo "$@"; fi; }
compose_services() { # <action...>: run docker compose for the shared services with every profile
    ( cd /etc/zeltro-cli && docker compose --profile '*' "$@" )
}
all_project_dirs() { # every directory in the projects folder (files are rewritten even without a compose file)
    local d
    for d in "$PROJECTS_DIR_PATH"/*/; do basename "${d%/}"; done
}
projects() { # every project directory with a compose file
    local d
    for d in "$PROJECTS_DIR_PATH"/*/; do
        d="${d%/}"
        [ -f "$d/docker-compose.yaml" ] || [ -f "$d/docker-compose.yml" ] || continue
        basename "$d"
    done
}

# Rewrite (or, with "scan", just list) project files that name the old hosts or network.
REWRITE_PY='
import os, re, sys, json
mode, root, backup = sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ""
names = sys.argv[4].split() if len(sys.argv) > 4 else []
# Longest first so podium-mongo-express is not taken as podium-mongo + "-express".
names.sort(key=len, reverse=True)
tok = re.compile(r"(?<![\w.-])podium-(cli_vpc|project|" + "|".join(map(re.escape, names)) + r")(?![\w-])")
skip_dirs = {".git", "node_modules", "vendor", ".venv", "venv", "__pycache__", ".next", ".nuxt", "dist", "build", "storage", "cache"}
out = []
for dirpath, dirs, files in os.walk(root):
    dirs[:] = [d for d in dirs if d not in skip_dirs]
    for f in files:
        p = os.path.join(dirpath, f)
        try:
            if os.path.islink(p) or os.path.getsize(p) > 2_000_000:
                continue
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\0" in data[:8192] or b"podium-" not in data:
            continue
        text = data.decode("utf-8", "surrogateescape")
        n = len(tok.findall(text))
        if not n:
            continue
        rel = os.path.relpath(p, root)
        out.append({"file": rel, "count": n})
        if mode == "apply":
            dst = os.path.join(backup, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "wb") as b:
                b.write(data)
            new = tok.sub(lambda m: "zeltro-" + m.group(1), text).encode("utf-8", "surrogateescape")
            st = os.stat(p)
            tmp = p + ".zeltro-migrate.tmp"
            with open(tmp, "wb") as w:
                w.write(new)
            os.chmod(tmp, st.st_mode & 0o7777)
            try:
                os.chown(tmp, st.st_uid, st.st_gid)
            except PermissionError:
                pass
            os.replace(tmp, p)
print(json.dumps(out))
'
SUFFIXES=""; for pair in $SERVICES; do SUFFIXES="$SUFFIXES ${pair#*:}"; done

current_project="$(env_get COMPOSE_PROJECT_NAME)"

# ---------------------------------------------------------------- projects-only -
if [ "$MODE" = "projects-only" ]; then
    BACKUP="$HOME/.zeltro/migrate-names-projects-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"; chmod 700 "$BACKUP"
    total=0
    for p in $(all_project_dirs); do
        json="$(python3 -c "$REWRITE_PY" apply "$PROJECTS_DIR_PATH/$p" "$BACKUP/$p" "$SUFFIXES")"
        n="$(printf '%s' "$json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
        [ "$n" = "0" ] || { echo-white "  $p: $n file(s)"; total=$((total + n)); }
    done
    echo-green "Rewrote $total project file(s). Originals: $BACKUP"
    exit 0
fi

# ---------------------------------------------------------------- remove-old ----
if [ "$MODE" = "remove-old" ]; then
    [ "$current_project" = "$NEW_PROJECT" ] || error "This machine hasn't been migrated (COMPOSE_PROJECT_NAME is ${current_project:-unset}). Nothing removed."
    vols="$(docker volume ls --format '{{.Name}}' | grep -E "^${OLD_PROJECT}_" || true)"
    [ -n "$vols" ] || { echo-green "No old ${OLD_PROJECT}_* volumes left."; exit 0; }
    for v in $vols; do docker volume rm "$v" >/dev/null && echo-white "  removed $v"; done
    echo-green "Old volumes removed."
    exit 0
fi

# ---------------------------------------------------------------- rollback ------
if [ "$MODE" = "rollback" ]; then
    [ -f "$ROLLBACK_DIR/manifest.json" ] || error "$ROLLBACK_DIR has no manifest.json; not a migrate-names backup."
    echo-yellow "Rolling back to the podium-* names from $ROLLBACK_DIR."
    echo-yellow "Anything written to the zeltro-* volumes since the migration will not be in the old ones."
    for p in $(projects); do ( cd "$PROJECTS_DIR_PATH/$p" && docker compose down >/dev/null 2>&1 ) || true; done
    compose_services down >/dev/null 2>&1 || true
    as_root_if_needed "$ENV_FILE" cp -p "$ROLLBACK_DIR/etc-zeltro-cli.env" "$ENV_FILE"
    ( cd "$ROLLBACK_DIR/projects" 2>/dev/null && find . -type f ) | while read -r f; do
        cp -p "$ROLLBACK_DIR/projects/${f#./}" "$PROJECTS_DIR_PATH/${f#./}"
    done
    "$SCRIPT_DIR/start_services.sh"
    for p in $(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["running_projects"]))' "$ROLLBACK_DIR/manifest.json"); do
        "$ZELTRO_BIN" up "$p" >/dev/null 2>&1 && echo-white "  started $p" || echo-yellow "  $p did not start; check: zeltro up $p"
    done
    echo-green "Rolled back. The zeltro-cli_* volumes were left in place; remove them by hand when you're sure."
    exit 0
fi

# ---------------------------------------------------------------- preview / run -
if [ "$current_project" = "$NEW_PROJECT" ] || { [ -z "$current_project" ] && ! docker network inspect "${OLD_PROJECT}_vpc" >/dev/null 2>&1; }; then
    echo-green "This machine already uses the zeltro-* names. Nothing to do."
    exit 0
fi
[ "$current_project" = "$OLD_PROJECT" ] || error "COMPOSE_PROJECT_NAME is '$current_project', not $OLD_PROJECT. Not a Podium-era machine; not touching it."

old_vols="$(docker volume ls --format '{{.Name}}' | grep -E "^${OLD_PROJECT}_" || true)"
for v in $old_vols; do
    nv="${NEW_PROJECT}_${v#${OLD_PROJECT}_}"
    docker volume inspect "$nv" >/dev/null 2>&1 && error "Volume $nv already exists. A previous run may have stopped half way; inspect it before trying again."
done
for pair in $SERVICES; do
    docker container inspect "${NEW_PREFIX}-${pair#*:}" >/dev/null 2>&1 && error "A container named ${NEW_PREFIX}-${pair#*:} already exists; it would clash with the renamed service."
done
docker network inspect "${NEW_PROJECT}_vpc" >/dev/null 2>&1 && error "A network named ${NEW_PROJECT}_vpc already exists."

# Every service is recreated from the CURRENT compose file. If a container runs a
# different image, or keeps its data at a different path, the recreated one
# would not read the copied data: a Postgres 18 volume under a Postgres 17
# container starts an EMPTY database. Refuse rather than migrate into that.
mismatch="$( cd /etc/zeltro-cli && docker compose --profile '*' config --format json 2>/dev/null | python3 -c '
import json, subprocess, sys
cfg = json.load(sys.stdin)
for name, svc in cfg.get("services", {}).items():
    c = svc.get("container_name") or name
    want_img = svc.get("image", "")
    want = sorted(v["target"] for v in svc.get("volumes", []) if v.get("type") == "volume" and v.get("source"))
    r = subprocess.run(["docker", "inspect", "-f", "{{.Config.Image}}|{{range .Mounts}}{{if eq .Type \"volume\"}}{{.Name}}={{.Destination}},{{end}}{{end}}", c], capture_output=True, text=True)
    if r.returncode:
        continue                                    # not created: nothing to carry over
    img, mnts = r.stdout.strip().split("|", 1)
    have = sorted(m.split("=", 1)[1] for m in mnts.strip(",").split(",") if m and "_" in m.split("=", 1)[0])
    if img != want_img or have != want:
        print("  %s runs %s with data at %s; the current setup would recreate it as %s with data at %s"
              % (c, img, ", ".join(have) or "-", want_img, ", ".join(want) or "-"))
' )" || error "Couldn't read the shared-services compose file in /etc/zeltro-cli."
if [ -n "$mismatch" ]; then
    echo-red "Some shared services don't match what Zeltro would recreate them as:"
    echo "$mismatch"
    error "Migrating now could start them with empty data. Nothing was changed. Bring them in line first (e.g. dump and restore the database across the version change), then run this again."
fi

echo-cyan "Migrating $(hostname) from podium-* to zeltro-* names"
echo-white ""
echo-white "Shared-service containers (recreated under the new names):"
for pair in $SERVICES; do
    c="${OLD_PREFIX}-${pair#*:}"
    docker container inspect "$c" >/dev/null 2>&1 && echo-white "  $c -> ${NEW_PREFIX}-${pair#*:}"
done
echo-white "Network: ${OLD_PROJECT}_vpc -> ${NEW_PROJECT}_vpc (same subnet, same addresses)"
echo-white "Volumes (copied; the old ones are kept):"
total_kb=0
for v in $old_vols; do
    kb="$(docker run --rm -v "$v":/v:ro alpine:3 du -sk /v 2>/dev/null | cut -f1)"; kb="${kb:-0}"
    total_kb=$((total_kb + kb))
    echo-white "  $v -> ${NEW_PROJECT}_${v#${OLD_PROJECT}_}  ($((kb / 1024)) MB)"
done
free_kb="$(df -k "$(docker info -f '{{.DockerRootDir}}' 2>/dev/null || echo /var/lib/docker)" 2>/dev/null | awk 'NR==2 {print $4}')"
echo-white "  total $((total_kb / 1024)) MB to copy; $((${free_kb:-0} / 1024)) MB free"
[ "${free_kb:-0}" -gt $((total_kb * 2)) ] || error "Not enough free disk space to copy the volumes safely (need about twice their size)."

echo-white "Project files that name the old hosts or network:"
running=""; plan_count=0
for p in $(all_project_dirs); do
    json="$(python3 -c "$REWRITE_PY" scan "$PROJECTS_DIR_PATH/$p" "" "$SUFFIXES")"
    n="$(printf '%s' "$json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
    if [ "$n" != "0" ]; then
        plan_count=$((plan_count + n))
        printf '%s' "$json" | python3 -c 'import json,sys; [print("  %s/%s (%d)" % (sys.argv[1], f["file"], f["count"])) for f in json.load(sys.stdin)]' "$p"
    fi
    docker container inspect -f '{{.State.Running}}' "$p" 2>/dev/null | grep -q true && running="$running $p"
done
echo-white "  $plan_count file(s)"
echo-white "Projects running now (stopped, then started again):${running:- none}"
echo-white ""

if [ "$MODE" = "preview" ]; then
    echo-yellow "Preview only; nothing was changed. Run 'zeltro migrate-names --yes' to do it."
    echo-white "Every project and the shared services are stopped while it runs (a few minutes)."
    exit 0
fi

# ------------------------------------------------------------------- run --------
BACKUP="$HOME/.zeltro/migrate-names-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP/projects"; chmod 700 "$BACKUP"
cp -p "$ENV_FILE" "$BACKUP/etc-zeltro-cli.env"
python3 -c 'import json,sys; json.dump({"running_projects": sys.argv[1].split(), "old_volumes": sys.argv[2].split()}, open(sys.argv[3],"w"))' "$running" "$old_vols" "$BACKUP/manifest.json"
echo-cyan "Backup: $BACKUP   (undo with: zeltro migrate-names --rollback $BACKUP)"

# Database listings to compare after the move. An engine that is running must
# answer, or the comparison would pass vacuously on two empty lists.
db_list() { # <engine> <container>: sorted database names, or nothing
    case "$1" in
        mariadb)  docker exec "$2" mariadb -uroot -Nse 'show databases' 2>/dev/null | sort | tr '\n' ' ' ;;
        postgres) docker exec "$2" psql -U root -d postgres -Atc 'select datname from pg_database order by 1' 2>/dev/null | tr '\n' ' ' ;;
        mongo)    docker exec "$2" mongosh --quiet -u root -p password --authenticationDatabase admin --eval 'db.adminCommand({listDatabases:1}).databases.map(d=>d.name).sort().join(" ")' 2>/dev/null | tr -d '\r' ;;
    esac
}
db_wait_list() { # <engine> <container>: wait up to ~90s for the engine to answer
    local i out=""
    for i in $(seq 1 45); do
        out="$(db_list "$1" "$2")"; [ -n "$out" ] && { printf '%s' "$out"; return 0; }
        sleep 2
    done
    return 1
}
DB_ENGINES=""
for eng in mariadb postgres mongo; do
    if docker container inspect -f '{{.State.Running}}' "${OLD_PREFIX}-$eng" 2>/dev/null | grep -q true; then
        lst="$(db_wait_list "$eng" "${OLD_PREFIX}-$eng")" || error "Couldn't list the databases in ${OLD_PREFIX}-$eng, so the move couldn't be verified. Nothing was changed."
        DB_ENGINES="$DB_ENGINES $eng"
        eval "before_$eng=\"\$lst\""
        echo-white "  $eng: $(echo "$lst" | wc -w | tr -d ' ') databases to carry over"
    fi
done

echo-cyan "Stopping projects and shared services ..."
for p in $(projects); do ( cd "$PROJECTS_DIR_PATH/$p" && docker compose down >/dev/null 2>&1 ) || true; done
compose_services down >/dev/null 2>&1 || true
# Anything still attached (a container Zeltro doesn't manage) would keep the old network alive.
if docker network inspect "${OLD_PROJECT}_vpc" >/dev/null 2>&1; then
    left="$(docker network inspect -f '{{range .Containers}}{{.Name}} {{end}}' "${OLD_PROJECT}_vpc")"
    [ -z "$left" ] || error "Containers still on ${OLD_PROJECT}_vpc: $left. Stop them, then run again (nothing was renamed yet; 'zeltro up' restores the projects)."
    docker network rm "${OLD_PROJECT}_vpc" >/dev/null
fi

# Until the .env is switched, nothing has been renamed: a failure here removes
# the half-made copies and brings the old setup back up by itself.
created_vols=""
undo_copy() {
    echo-yellow "Putting things back the way they were ..."
    for nv in $created_vols; do docker volume rm "$nv" >/dev/null 2>&1 || true; done
    "$SCRIPT_DIR/start_services.sh" >/dev/null 2>&1 || true
    for p in $running; do "$ZELTRO_BIN" up "$p" >/dev/null 2>&1 || echo-yellow "  $p did not start; try: zeltro up $p"; done
}

echo-cyan "Copying volumes ..."
for v in $old_vols; do
    nv="${NEW_PROJECT}_${v#${OLD_PROJECT}_}"
    docker volume create --label "com.docker.compose.project=${NEW_PROJECT}" --label "com.docker.compose.volume=${v#${OLD_PROJECT}_}" "$nv" >/dev/null
    created_vols="$created_vols $nv"
    if ! docker run --rm -v "$v":/from:ro -v "$nv":/to alpine:3 sh -c 'cp -a /from/. /to/'; then
        undo_copy; error "Copying $v failed. Nothing was renamed; the old setup is running again."
    fi
    a="$(zeltro_volume_fingerprint "$v")"; b="$(zeltro_volume_fingerprint "$nv")"
    if [ -z "$a" ] || [ "$a" != "$b" ]; then
        undo_copy; error "The copy of $v does not match the original (${a:-unreadable} vs ${b:-unreadable}). Nothing was renamed; the old setup is running again."
    fi
    echo-white "  $v -> $nv  verified (${a:0:12})"
done

echo-cyan "Switching names in $ENV_FILE ..."
tmp_env="$(mktemp)"
python3 - "$ENV_FILE" "$tmp_env" <<'PYENV'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
out, skipping = [], False
for line in open(src).read().splitlines():
    # The old rebrand's explanation of why these names were pinned to podium;
    # it is false once the machine is migrated.
    if line.startswith("# --- rebrand migration (podium -> zeltro)"):
        skipping = True
        continue
    if skipping:
        if line.startswith("#"):
            continue
        skipping = False
    line = re.sub(r'^COMPOSE_PROJECT_NAME="?podium-cli"?$', "COMPOSE_PROJECT_NAME=zeltro-cli", line)
    line = re.sub(r'^SERVICE_PREFIX="?podium"?$', "SERVICE_PREFIX=zeltro", line)
    line = re.sub(r'^([A-Z]+_CONTAINER_NAME)="?podium-([a-z-]+)"?$', r"\1=zeltro-\2", line)
    line = re.sub(r'^DEBUG_LOG_PATH=/tmp/podium-cli-debug\.log$', "DEBUG_LOG_PATH=/tmp/zeltro-cli-debug.log", line)
    if line.startswith("#"):
        line = line.replace("Podium", "Zeltro")
    out.append(line)
open(dst, "w").write("\n".join(out) + "\n")
PYENV
as_root_if_needed "$ENV_FILE" cp "$tmp_env" "$ENV_FILE"; rm -f "$tmp_env"
grep -qiE "^[A-Z_]*=\"?${OLD_PREFIX}" "$ENV_FILE" && echo-yellow "  some podium values remain in $ENV_FILE; check them"

echo-cyan "Rewriting project files ..."
for p in $(all_project_dirs); do
    python3 -c "$REWRITE_PY" apply "$PROJECTS_DIR_PATH/$p" "$BACKUP/projects/$p" "$SUFFIXES" >/dev/null
done

echo-cyan "Starting shared services under the new names ..."
# shellcheck disable=SC1090
source "$ENV_FILE"
"$SCRIPT_DIR/start_services.sh" >/dev/null
db_bad=""
for eng in $DB_ENGINES; do
    eval "b=\"\$before_$eng\""
    a="$(db_wait_list "$eng" "${NEW_PREFIX}-$eng" || true)"
    if [ -n "$a" ] && [ "$a" = "$b" ]; then
        echo-white "  $eng: all $(echo "$a" | wc -w | tr -d ' ') databases present"
    else
        echo-red "  $eng databases differ!"; echo-red "    before: $b"; echo-red "    after:  ${a:-(no answer)}"
        db_bad="$db_bad $eng"
    fi
done
if [ -n "$db_bad" ]; then
    # Don't start projects against missing data. The old volumes are untouched.
    error "The databases in:$db_bad don't match after the move. Projects were NOT started. Undo with: zeltro migrate-names --rollback $BACKUP"
fi

echo-cyan "Starting the projects that were running ..."
failed=""
for p in $running; do
    if "$ZELTRO_BIN" up "$p" >/dev/null 2>&1; then echo-white "  $p up"; else echo-yellow "  $p did not start"; failed="$failed $p"; fi
done

echo-white ""
echo-green "Done: $(hostname) now uses zeltro-* names."
[ -z "$failed" ] || echo-yellow "Not started:$failed. Try 'zeltro up <name>' and check 'docker logs <name>'."
echo-white "The old ${OLD_PROJECT}_* volumes are still there. When everything checks out:"
echo-white "  zeltro migrate-names --remove-old-volumes"
echo-white "To undo instead: zeltro migrate-names --rollback $BACKUP"
cd "$ORIG_DIR"
