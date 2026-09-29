#!/bin/bash
# Test x-metadata values, especially `idea` (the Create with AI prompt a project
# came from): any text must round-trip byte for byte, must never break the
# compose file for Docker Compose, and must never be read as another key.
#
#   bash tests/metadata-idea.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }

C="$T/docker-compose.yaml"
cat > "$C" <<'EOF'
services:
  web:
    image: alpine:3
    container_name: demo
    x-metadata:
      name: "My App"
      emoji: "🚀"
      last_on: 2026-09-01T10:00:00Z
EOF

fn() { ( set +u; source "$REPO/src/scripts/functions.sh" >/dev/null 2>&1; "$@" ); }
roundtrip() { # <label> <file with value>: set idea from the file, read it back, compare bytes
    fn set_x_metadata_key_file "$C" demo idea "$2" || { bad "$1: write failed"; return; }
    fn read_x_metadata_json "$C" full | python3 -c 'import json,sys; sys.stdout.buffer.write(json.load(sys.stdin)["idea"].encode("utf-8","surrogateescape"))' > "$T/back"
    cmp -s "$2" "$T/back" && ok "$1: round-trips byte for byte" || bad "$1: differs ($(wc -c < "$2") vs $(wc -c < "$T/back") bytes)"
}

printf 'Build a recipe site.\nIt says "hello" and \x27hi\x27.\nRun $(rm -rf /) and `whoami` and ${oops and $HOME\nkey: value: more\n- leading dash\nstatus: disabled\nname: Evil\n\ttabbed \\backslash\\ \\n not-a-newline\n🍕 日本語 café\r\nwindows line\r\n\n\n' > "$T/nasty"
roundtrip "multi-line with quotes, \$, backticks, colons, dashes, unicode, CRLF, trailing newlines" "$T/nasty"

[ "$(fn read_x_metadata_key "$C" status)" = "" ] && ok "a 'status: disabled' line inside the idea is not the project's status" || bad "idea text read as status"
[ "$(fn read_x_metadata_key "$C" name)" = "My App" ] && ok "a 'name: Evil' line inside the idea is not the name" || bad "name clobbered: $(fn read_x_metadata_key "$C" name)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["display_name"]=="My App" and d["emoji"]=="🚀" and d["last_on"]=="2026-09-01T10:00:00Z"' "$(fn read_x_metadata_json "$C")" \
    && ok "other keys (quoted, emoji, unquoted legacy) read unchanged" || bad "other keys changed"
[ "$(grep -c 'idea:' "$C")" = 1 ] && [ "$(awk '/x-metadata:/{f=1;next} f && /^      [a-z_]+:/{n++} END{print n}' "$C")" = 4 ] \
    && ok "the idea is one line in the compose file" || bad "idea spilled onto several lines"

python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert "idea" not in d and d["has_idea"] is True' "$(fn read_x_metadata_json "$C")" \
    && ok "status-style read: no idea text, has_idea true" || bad "default read includes the idea"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    (cd "$T" && docker compose config -q 2>"$T/cerr") && ok "Docker Compose accepts the file (no interpolation of \$, \${oops)" \
        || bad "docker compose config failed: $(cat "$T/cerr")"
    (cd "$T" && docker compose config 2>/dev/null) | grep -q 'rm -rf' && ok "Compose sees the idea text" || bad "Compose lost the idea"
else
    ok "(docker compose not available, skipped)"
fi

printf 'caf\xe9 is latin-1 \xff\xfe bytes\n' > "$T/binary"
roundtrip "invalid UTF-8 bytes" "$T/binary"
python3 -c 'print(("x" * 99 + "\n") * 2048, end="")' > "$T/big"
roundtrip "200 KB idea" "$T/big"

printf 'value with $5 and "quotes"' > "$T/desc"
fn set_x_metadata_key "$C" demo description "$(cat "$T/desc")"
[ "$(fn read_x_metadata_key "$C" description)" = "$(cat "$T/desc")" ] && ok "description with \$ and quotes round-trips" || bad "description: $(fn read_x_metadata_key "$C" description)"

fn set_x_metadata_key_file "$C" demo idea /dev/null delete
grep -q 'idea:' "$C" && bad "delete left the idea" || ok "delete removes the idea"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert "has_idea" not in d and d["display_name"]=="My App"' "$(fn read_x_metadata_json "$C")" \
    && ok "delete leaves the other keys" || bad "delete disturbed other keys"

printf 'services:\n  web:\n    image: alpine:3\n    container_name: fresh\n' > "$C"
printf 'first idea' > "$T/one"; fn set_x_metadata_key_file "$C" fresh idea "$T/one"
grep -q '^    x-metadata:$' "$C" && [ "$(fn read_x_metadata_key "$C" idea)" = "first idea" ] && ok "creates the x-metadata block when missing" || bad "block not created"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
