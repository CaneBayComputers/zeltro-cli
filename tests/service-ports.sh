#!/bin/bash
# start-services: a shared-service port that another container (an old Podium
# install's podium-mailhog) or a program outside Docker holds is reported by
# name before `docker compose up`, with the fix, and nothing is stopped for the
# user. Uses a fake `docker` on PATH; no containers are touched.
#
#   bash tests/service-ports.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }

[ -f /etc/zeltro-cli/.env ] || { echo "skipped: needs a configured Zeltro (/etc/zeltro-cli/.env)"; exit 0; }

# FAKE_PORT: the port compose publishes for mailhog. FAKE_HOLDER: the container
# `docker ps --filter publish=` reports. FAKE_RUNNING=1: zeltro-mailhog is up.
mkdir -p "$T/bin" "$T/home"
cat > "$T/bin/docker" <<FAKE
#!/bin/bash
echo "\$*" >> "$T/docker.log"
case "\$1 \$2" in
    "info "*) exit 0 ;;
    "container inspect")
        [ "\$3" = "-f" ] || exit 1
        [ "\${FAKE_RUNNING:-0}" = "1" ] && echo true || echo false; exit 0 ;;
    "ps --filter") [ "\$3" = "publish=\${FAKE_PORT}" ] && [ -n "\${FAKE_HOLDER:-}" ] && echo "\$FAKE_HOLDER"; exit 0 ;;
esac
if [ "\$1" = "compose" ]; then
    case " \$* " in
        *" config "*) echo '{"services": {"mailhog": {"container_name": "zeltro-mailhog", "ports": [{"target": 8025, "published": "'"\${FAKE_PORT}"'", "protocol": "tcp"}]}}}' ;;
        *" up "*) echo "UP" >> "$T/up.log"; [ "\${FAKE_UP_FAIL:-0}" = "1" ] && { echo "Bind for 0.0.0.0:\${FAKE_PORT} failed: port is already allocated" >&2; exit 1; } ;;
    esac
    exit 0
fi
exit 0
FAKE
chmod +x "$T/bin/docker"

# A port nothing on this machine listens on.
FREE=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')

run() { # env assignments..., then start-services args
    ( export HOME="$T/home" PATH="$T/bin:$PATH" NO_COLOR=1; env "$@" "$REPO/src/zeltro" start-services --json-output 2>/dev/null </dev/null | tail -n 1 )
}
field() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); v=d; [v := v[k] if not k.isdigit() else v[int(k)] for k in sys.argv[2].split(".")]; print(v)' "$1" "$2" 2>/dev/null; }

echo "podium-mailhog holds 8025"
rm -f "$T/up.log" "$T/docker.log"
out="$(run FAKE_PORT=$FREE FAKE_HOLDER=podium-mailhog)"
check "error code" "$(field "$out" error)" "port_conflict"
check "names the port" "$(field "$out" conflicts.0.port)" "$FREE"
check "names the container" "$(field "$out" conflicts.0.container)" "podium-mailhog"
check "knows it's Podium" "$(field "$out" podium)" "True"
check "gives the fix" "$(field "$out" fix)" "docker update --restart=no podium-mailhog && docker stop podium-mailhog"
check "compose up never ran" "$([ -f "$T/up.log" ] && echo ran || echo no)" "no"
check "nothing stopped or removed" "$(grep -cE '^(stop|rm|update|kill|volume|run) ' "$T/docker.log")" "0"

mkdir -p "$T/home/podium-projects/shop/" && touch "$T/home/podium-projects/shop/docker-compose.yaml"
out="$(run FAKE_PORT=$FREE FAKE_HOLDER=podium-mailhog)"
check "mentions Podium's projects" "$(field "$out" message | grep -c "Podium still has 1 project(s) in $T/home/podium-projects")" "1"
rm -rf "$T/home/podium-projects"

echo "another container"
out="$(run FAKE_PORT=$FREE FAKE_HOLDER=mailpit)"
check "named, not called Podium" "$(field "$out" conflicts.0.container) $(field "$out" podium)" "mailpit False"

echo "a program outside Docker"
python3 -c 'import socket,time,sys; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(5); time.sleep(30)' "$FREE" &
lp=$!; sleep 0.5
out="$(run FAKE_PORT=$FREE)"
kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
check "error code" "$(field "$out" error)" "port_conflict"
check "no container named" "$(field "$out" conflicts.0.container)" ""
check "no docker fix offered" "$(field "$out" fix)" ""

echo "no conflict"
rm -f "$T/up.log"
out="$(run FAKE_PORT=$FREE)"
check "starts" "$(field "$out" status)" "success"
check "compose up ran" "$(cat "$T/up.log" 2>/dev/null)" "UP"
rm -f "$T/up.log"
out="$(run FAKE_PORT=$FREE FAKE_RUNNING=1 FAKE_HOLDER=zeltro-mailhog)"
check "already running: our own port isn't a conflict" "$(field "$out" status)" "success"

echo "compose up fails anyway"
out="$(run FAKE_PORT=$FREE FAKE_UP_FAIL=1)"
check "JSON error, not a silent exit" "$(field "$out" error)" "start_failed"

echo "human output"
msg="$( export HOME="$T/home" PATH="$T/bin:$PATH" NO_COLOR=1 FAKE_PORT=$FREE FAKE_HOLDER=podium-mailhog; "$REPO/src/zeltro" start-services 2>&1 </dev/null; echo "rc=$?")"
check "says which container" "$(echo "$msg" | grep -c "Port $FREE is held by the container podium-mailhog")" "1"
check "exits 1" "$(echo "$msg" | tail -n 1)" "rc=1"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
