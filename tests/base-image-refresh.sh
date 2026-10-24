#!/bin/bash
# zeltro_refresh_base_images: starting a project re-pulls a canebaycomputers/cbc:* base image
# the machine already has (at most once a day), so a fix pushed to the image
# reaches machines that pulled it before. Uses a fake `docker` on PATH; no
# images are touched.
#
#   bash tests/base-image-refresh.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }

# FAKE_HAVE: images present ("a b"). FAKE_PULL_FAIL=1: pulls fail.
# FAKE_NEW=1: a pull changes the image id.
mkdir -p "$T/bin" "$T/home" "$T/p"
cat > "$T/bin/docker" <<FAKE
#!/bin/bash
case "\$1 \$2" in
    "image inspect")
        img="\${@: -1}"
        case " \${FAKE_HAVE:-} " in *" \$img "*) ;; *) exit 1 ;; esac
        [ -f "$T/pulled-\${img//[\/:]/_}" ] && [ "\${FAKE_NEW:-0}" = 1 ] && echo sha256:new || echo sha256:old ;;
    "pull -q")
        echo "\$3" >> "$T/pulls.log"
        [ "\${FAKE_PULL_FAIL:-0}" = 1 ] && exit 1
        touch "$T/pulled-\${3//[\/:]/_}" ;;
esac
exit 0
FAKE
chmod +x "$T/bin/docker"

refresh() { # env assignments...: run the helper on $T/p/docker-compose.yaml
    ( export HOME="$T/home" PATH="$T/bin:$PATH" NO_COLOR=1; unset XDG_CACHE_HOME
      set +u; source "$REPO/src/scripts/functions.sh" >/dev/null 2>&1
      for a in "$@"; do export "$a"; done
      set -e; zeltro_refresh_base_images "$T/p/docker-compose.yaml"; echo "__REACHED__" )
}
pulls() { [ -f "$T/pulls.log" ] && tr '\n' ' ' < "$T/pulls.log" | sed 's/ $//'; rm -f "$T/pulls.log"; }
fresh() { rm -rf "$T/home/.cache" "$T"/pulled-* "$T/pulls.log"; }

cat > "$T/p/docker-compose.yaml" <<'EOF'
services:
  server:
    image: canebaycomputers/cbc:nginx-node
  worker:
    image: "canebaycomputers/cbc:nginx-node"
  db:
    image: postgres:16
EOF

echo "image already here"
fresh
out="$(refresh FAKE_HAVE=canebaycomputers/cbc:nginx-node)"
check "returns normally" "$(echo "$out" | grep -c __REACHED__)" "1"
check "pulled once (quoted duplicate folded)" "$(pulls)" "canebaycomputers/cbc:nginx-node"
check "says it's checking" "$(echo "$out" | grep -c "Checking for a newer canebaycomputers/cbc:nginx-node")" "1"
check "unchanged: no 'Updated'" "$(echo "$out" | grep -c "Updated")" "0"

echo "within a day"
refresh FAKE_HAVE=canebaycomputers/cbc:nginx-node >/dev/null
check "not pulled again" "$(pulls)" ""

echo "a day later"
rm -f "$T"/pulled-*
touch -t "$(date -d '-2 days' +%Y%m%d%H%M 2>/dev/null || date -v-2d +%Y%m%d%H%M)" "$T/home/.cache/zeltro/image-checks/canebaycomputers_cbc_nginx-node"
out="$(refresh FAKE_HAVE=canebaycomputers/cbc:nginx-node FAKE_NEW=1)"
check "pulled again" "$(pulls)" "canebaycomputers/cbc:nginx-node"
check "says it updated" "$(echo "$out" | grep -c "Updated canebaycomputers/cbc:nginx-node")" "1"

echo "image not here yet"
fresh
refresh FAKE_HAVE= >/dev/null
check "left to compose" "$(pulls)" ""
check "no stamp" "$(ls "$T/home/.cache/zeltro/image-checks" 2>/dev/null | wc -l | tr -d ' ')" "0"

echo "offline"
fresh
out="$(refresh FAKE_HAVE=canebaycomputers/cbc:nginx-node FAKE_PULL_FAIL=1)"
check "not fatal" "$(echo "$out" | grep -c __REACHED__)" "1"
pulls >/dev/null
refresh FAKE_HAVE=canebaycomputers/cbc:nginx-node >/dev/null
check "retried next time" "$(pulls)" "canebaycomputers/cbc:nginx-node"

echo "other images and opt-out"
fresh
printf 'services:\n  app:\n    image: canebaycomputers/cbc:nginx-php8\n  db:\n    image: postgres:16\n' > "$T/p/docker-compose.yaml"
refresh "FAKE_HAVE=canebaycomputers/cbc:nginx-php8 postgres:16" >/dev/null
check "only the base image" "$(pulls)" "canebaycomputers/cbc:nginx-php8"
fresh
refresh FAKE_HAVE=canebaycomputers/cbc:nginx-php8 ZELTRO_NO_IMAGE_REFRESH=1 >/dev/null
check "ZELTRO_NO_IMAGE_REFRESH=1 skips" "$(pulls)" ""
rm -f "$T/p/docker-compose.yaml"
check "no compose file: fine" "$(refresh | grep -c __REACHED__)" "1"

echo "JSON mode prints nothing"
fresh
printf 'services:\n  app:\n    image: canebaycomputers/cbc:nginx-node\n' > "$T/p/docker-compose.yaml"
check "stdout empty" "$(refresh FAKE_HAVE=canebaycomputers/cbc:nginx-node FAKE_NEW=1 JSON_OUTPUT=1 | grep -v __REACHED__)" ""

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
