#!/bin/bash
# zeltro uninstall against a fake Docker and a scratch filesystem root: it must
# remove every Zeltro container (services by compose project, projects by
# working dir) before networks, volumes and images; never prompt, prune or
# disconnect; leave other containers and the projects folder alone; and list
# anything it couldn't remove with a non-zero exit.
#
# 2026-10-22 on shop-work-desk the old script stopped none of the services
# (it looked up `"${MARIADB_CONTAINER_NAME:-zeltro-mariadb}"` literally), said
# volumes and images were removed when Docker had refused, pulled the network
# out from under the running services and renamed project compose files.
#
# Touches no real Docker resource or system file. Needs /etc/zeltro-cli/.env
# (functions.sh loads it).
#
#   bash tests/uninstall.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }
has()   { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1: [$3] not in output"; fi; }
hasnt() { if grep -qF -- "$3" <<<"$2"; then bad "$1: [$3] in output"; else ok "$1"; fi; }

# The fake docker. State, one record per line, tab-separated:
#   containers: name project working_dir image networks(comma)
#   networks:   name project       volumes: name project       images: ref
#   stuck:      container names that refuse removal
#   compose_images: what `docker compose config --images` prints
# Every call is appended to calls.
mkdir -p "$T/bin"
cat > "$T/bin/docker" <<'FAKE'
#!/bin/bash
S="$FAKE_DOCKER_STATE"
echo "$*" >> "$S/calls"
touch "$S/containers" "$S/networks" "$S/volumes" "$S/images" "$S/stuck" "$S/compose_images"
col() { awk -F'\t' -v c="$1" '{print $c}' "$2"; }
exists() { awk -F'\t' -v n="$2" '$1 == n {f=1} END {exit !f}' "$S/$1"; }
drop() { awk -F'\t' -v n="$2" '$1 != n' "$S/$1" > "$S/$1.tmp"; mv "$S/$1.tmp" "$S/$1"; }
label_filter() { # <file> <args...>: names, filtered by --filter label=com.docker.compose.project=P
    local p=""; for a in "$@"; do case "$a" in label=com.docker.compose.project=*) p="${a#*=}"; p="${p#*=}" ;; esac; done
    if [ -n "$p" ]; then awk -F'\t' -v p="$p" '$2 == p {print $1}' "$S/$1"; else col 1 "$S/$1"; fi
}
case "$1" in
    info) exit 0 ;;
    ps)
        anc=""; for a in "$@"; do case "$a" in ancestor=*) anc="${a#ancestor=}" ;; esac; done
        if [ -n "$anc" ]; then awk -F'\t' -v i="$anc" '$4 == i {print $1}' "$S/containers"
        else awk -F'\t' '{print $1"\t"$2"\t"$3"\t"$4}' "$S/containers"; fi ;;
    rm)
        for a in "${@:2}"; do case "$a" in -*) ;; *)
            grep -qx "$a" "$S/stuck" && { echo "Error: cannot remove $a" >&2; exit 1; }
            drop containers "$a" ;; esac; done ;;
    container) exists containers "$3" ;;
    network)
        case "$2" in
            ls) label_filter networks "$@" ;;
            inspect) exists networks "$3" || exit 1
                     awk -F'\t' -v n="$3" '{k=split($5,a,","); for(i=1;i<=k;i++) if(a[i]==n) printf "%s ", $1}' "$S/containers" ;;
            rm) u=$(awk -F'\t' -v n="$3" '{k=split($5,a,","); for(i=1;i<=k;i++) if(a[i]==n) print $1}' "$S/containers")
                [ -z "$u" ] || { echo "Error: network $3 has active endpoints" >&2; exit 1; }
                drop networks "$3" ;;
            *) exit 1 ;;
        esac ;;
    volume)
        case "$2" in
            ls) label_filter volumes "$@" ;;
            inspect) exists volumes "$3" ;;
            rm) drop volumes "$3" ;;
        esac ;;
    image) exists images "$3" ;;
    rmi) awk -F'\t' -v i="$2" '$4 == i {f=1} END {exit f}' "$S/containers" || { echo "Error: image in use" >&2; exit 1; }
         drop images "$2" ;;
    compose) cat "$S/compose_images" ;;
    *) exit 1 ;;
esac
FAKE
chmod +x "$T/bin/docker"

# Fake package managers: packages listed in <state>/pkgs are "installed".
# They also keep the test from ever reaching the real apt.
cat > "$T/bin/dpkg" <<'FAKE'
#!/bin/bash
[ "$1" = "-s" ] && grep -qx "$2" "$FAKE_DOCKER_STATE/pkgs" 2>/dev/null
FAKE
cat > "$T/bin/apt-get" <<'FAKE'
#!/bin/bash
echo "apt-get $*" >> "$FAKE_DOCKER_STATE/calls"
name="${@: -1}"; grep -vx "$name" "$FAKE_DOCKER_STATE/pkgs" > "$FAKE_DOCKER_STATE/pkgs.tmp"; mv "$FAKE_DOCKER_STATE/pkgs.tmp" "$FAKE_DOCKER_STATE/pkgs"
FAKE
for f in rpm pacman dnf; do printf '#!/bin/sh
exit 1
' > "$T/bin/$f"; done
chmod +x "$T/bin/dpkg" "$T/bin/apt-get" "$T/bin/rpm" "$T/bin/pacman" "$T/bin/dnf"

# A fresh world: a projects folder, a scratch system root and Docker state.
setup() { # <name>
    W="$T/$1"; S="$W/docker"; ROOT="$W/root"; PD="$W/projects"; H="$W/home"
    mkdir -p "$S" "$PD/blog" "$PD/bugsink" "$PD/notes" "$W/elsewhere/linked" "$H/.config/zeltro-gui" \
             "$ROOT/etc/zeltro-cli" "$ROOT/etc/apt/sources.list.d" "$ROOT/etc/apt/keyrings" \
             "$ROOT/usr/local/bin" "$ROOT/usr/local/share/zeltro-cli/src"
    printf 'services: {}\n' > "$PD/blog/docker-compose.yaml"
    ln -s "$W/elsewhere/linked" "$PD/linked"
    echo x > "$ROOT/etc/zeltro-cli/.env"; echo x > "$ROOT/etc/zeltro-cli/docker-compose.yaml"
    echo x > "$ROOT/etc/apt/sources.list.d/zeltro.list"; echo x > "$ROOT/etc/apt/keyrings/zeltro.asc"
    echo x > "$ROOT/usr/local/bin/zeltro"; echo x > "$H/.config/zeltro-gui/config.json"
    mkdir -p "$ROOT/etc/bash_completion.d" "$ROOT/usr/share/bash-completion/completions" "$ROOT/var/lib/apt/lists" \
             "$ROOT/tmp/zeltro-update-Ab12" "$ROOT/Applications/Zeltro.app" "$H/.zeltro/bus" "$H/.cache/zeltro"
    ln -s /nonexistent/zeltro.bash "$ROOT/etc/bash_completion.d/zeltro"
    ln -s /nonexistent/zeltro.bash "$ROOT/usr/share/bash-completion/completions/zeltro"
    echo x > "$ROOT/var/lib/apt/lists/packages.zeltro.ai_apt_dists_stable_InRelease"
    echo x > "$ROOT/var/lib/apt/lists/archive.ubuntu.com_dists_noble_InRelease"
    echo x > "$ROOT/tmp/zeltro-update-Ab12/Zeltro.deb"; echo x > "$ROOT/tmp/other-file"
    printf 'zeltro-gui\ndocker-ce\n' > "$S/pkgs"
    tab=$'\t'
    cat > "$S/containers" <<EOF
zeltro-mariadb${tab}zeltro-cli${tab}/etc/zeltro-cli${tab}mariadb:11${tab}zeltro-cli_vpc
zeltro-redis${tab}zeltro-cli${tab}/etc/zeltro-cli${tab}redis:7${tab}zeltro-cli_vpc
blog${tab}blog${tab}$PD/blog${tab}canebaycomputers/cbc:nginx-php8${tab}zeltro-cli_vpc,blog_default
bugsink-app-1${tab}bugsink${tab}$PD/bugsink${tab}bugsink/bugsink:2${tab}zeltro-cli_vpc
other${tab}other${tab}/srv/other${tab}nginx:1${tab}other_default
linked${tab}linked${tab}$W/elsewhere/linked${tab}nginx:1${tab}other_default
EOF
    printf 'zeltro-cli_vpc\tzeltro-cli\nblog_default\tblog\nother_default\tother\n' > "$S/networks"
    printf 'zeltro-cli_mysql_data\tzeltro-cli\nzeltro-cli_redis_data\tzeltro-cli\nother_data\tother\n' > "$S/volumes"
    printf 'mariadb:11\nredis:7\ncanebaycomputers/cbc:nginx-php8\nbugsink/bugsink:2\nnginx:1\nmailhog/mailhog\n' > "$S/images"
    printf 'mariadb:11\nredis:7\nmailhog/mailhog\n' > "$S/compose_images"
}
run() { # <args...>; sets OUT and RC
    OUT=$( export PATH="$T/bin:$PATH" FAKE_DOCKER_STATE="$S" ZELTRO_TEST_ROOT="$ROOT" \
                  ZELTRO_TEST_PROJECTS_DIR="$PD" HOME="$H" NO_COLOR=1
           timeout 60 bash "$REPO/src/scripts/uninstall.sh" "$@" </dev/null 2>&1 ); RC=$?
}
names() { cut -f1 "$S/$1" | sort | tr '\n' ' '; }

echo "default: containers and networks go; data, images, config and projects stay"
setup a; run
check "exit 0" "$RC" "0"
check "only the unrelated containers remain" "$(names containers)" "linked other "
check "networks" "$(names networks)" "other_default "
check "volumes kept" "$(names volumes)" "other_data zeltro-cli_mysql_data zeltro-cli_redis_data "
check "images kept" "$(wc -l < "$S/images" | tr -d ' ')" "6"
check "project compose untouched" "$(ls "$PD/blog")" "docker-compose.yaml"
check "config kept" "$(ls -A "$ROOT/etc/zeltro-cli" | LC_ALL=C sort | tr '\n' ' ')" ".env docker-compose.yaml "
check "CLI removed" "$(ls "$ROOT/usr/local/bin" "$ROOT/usr/local/share" | tr -d '\n')" "$ROOT/usr/local/bin:$ROOT/usr/local/share:"
has "says data volumes were kept" "$OUT" "Kept data volumes (remove with --delete-data): zeltro-cli_mysql_data zeltro-cli_redis_data"
hasnt "never prompts" "$OUT" "(y/N)"
hasnt "no prune" "$(cat "$S/calls")" "prune"
hasnt "no disconnect" "$(cat "$S/calls")" "disconnect"
check "containers removed before any network" \
    "$(grep -n '' "$S/calls" | awk -F: '/:rm -f/ {r=$1} /:network rm/ && !n {n=$1} END {print (r < n) ? "yes" : "no"}')" "yes"

echo "a network another container still uses is reported, not disconnected"
setup b; printf 'intruder\tx\t/srv/x\tnginx:1\tzeltro-cli_vpc\n' >> "$S/containers"; run
check "exit 1" "$RC" "1"
has "listed" "$OUT" "network zeltro-cli_vpc (still used by: intruder)"
check "intruder still there" "$(names containers)" "intruder linked other "

echo "--purge: everything Zeltro put here except the projects folder"
setup c; sed -i 's|^\(other\t.*\t\)nginx:1\t|\1redis:7\t|' "$S/containers"
mkdir -p "$H/.local/bin"; printf '#!/bin/sh\n# Zeltro WSL browser opener: test\n' > "$H/.local/bin/xdg-open"; echo x > "$H/.local/bin/other-tool"
run --purge
check "exit 0 (a shared image is kept, not a failure)" "$RC" "0"
check "Zeltro volumes gone" "$(names volumes)" "other_data "
check "the shared and unrelated images left" "$(names images)" "nginx:1 redis:7 "
has "shared image reported" "$OUT" "kept image redis:7, in use by other"
check "GUI package purged, Docker's kept" "$(cat "$S/pkgs")" "docker-ce"
check "apt lists: only Zeltro's gone" "$(ls "$ROOT/var/lib/apt/lists")" "archive.ubuntu.com_dists_noble_InRelease"
check "completions, update downloads, app bundle gone" \
    "$(ls -A "$ROOT/etc/bash_completion.d" "$ROOT/usr/share/bash-completion/completions" "$ROOT/Applications" "$ROOT/tmp" | grep -v '^/\|^$' | tr '\n' ' ')" "other-file "
check "~/.zeltro and ~/.cache/zeltro gone" "$(ls -A "$H" "$H/.cache" | grep -v '^/\|^$' | tr '\n' ' ')" ".cache .config .local "
check "Zeltro's WSL xdg-open gone, other tools kept" "$(ls -A "$H/.local/bin")" "other-tool"
hasnt "unrelated image not touched" "$(cat "$S/calls")" "rmi nginx:1"
has "compose-only image removed" "$OUT" "removed image mailhog/mailhog"
check "config gone" "$(find "$ROOT/etc" -type f | wc -l | tr -d ' ')" "0"
check "app settings gone" "$(ls "$H/.config")" ""
check "projects folder intact" "$(ls "$PD" | tr '\n' ' ')" "blog bugsink linked notes "
setup c2; sed -i '/^other\t/d;/^linked\t/d' "$S/containers"; run --purge
check "purge with nothing shared: exit 0" "$RC" "0"

echo "a container Docker refuses to remove: reported in JSON, exit 1"
setup d; echo zeltro-redis > "$S/stuck"; run --json-output
check "exit 1" "$RC" "1"
check "JSON status and leftovers" "$(python3 -c 'import json,sys; d=json.loads(sys.argv[1].splitlines()[-1]); print(d["status"], d["left"])' "$OUT" 2>&1)" \
    "incomplete ['container zeltro-redis', 'network zeltro-cli_vpc (still used by: zeltro-redis)']"
check "only JSON printed" "$(wc -l <<<"$OUT" | tr -d ' ')" "1"

echo "default leaves the app, its settings and ~/.zeltro alone"
setup f; run
check "GUI package kept" "$(head -1 "$S/pkgs")" "zeltro-gui"
check "~/.zeltro kept" "$(ls -A "$H/.zeltro")" "bus"
hasnt "no apt call" "$(cat "$S/calls")" "apt-get"

echo "options"
setup e; run --bogus
check "unknown option fails" "$RC" "1"
check "and changes nothing" "$(wc -l < "$S/containers" | tr -d ' ')" "6"
run --help; has "help lists --purge" "$OUT" "--purge"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
