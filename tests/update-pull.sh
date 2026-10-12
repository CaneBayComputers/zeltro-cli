#!/bin/bash
# zeltro update's git pull: a mode-only local change (the installers chmod +x
# every script) must not block an update, and a pull that really fails must
# exit non-zero. Runs update.sh from throwaway clones of this repo; touches no
# real install and no network. Needs /etc/zeltro-cli/.env (pre_check loads it).
#
#   bash tests/update-pull.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export ZELTRO_TEST_PROJECTS_DIR="$T/projects"
mkdir -p "$ZELTRO_TEST_PROJECTS_DIR"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }
g() { git -c user.name=t -c user.email=t@t "$@"; }

echo "every script is committed executable"
check "no 100644 scripts" "$(git -C "$REPO" ls-files -s src/scripts/'*.sh' | awk '$1 != "100755" {print $4}')" ""

# "origin" stands in for GitHub; "install" for /usr/local/share/zeltro-cli.
F=src/scripts/classify.sh
git clone -q "$REPO" "$T/origin"
g -C "$T/origin" update-index --chmod=-x "$F"
g -C "$T/origin" commit -qm "file committed without +x"
git clone -q "$T/origin" "$T/install"
chmod +x "$T/install/src/scripts"/*.sh

echo "installer chmod leaves a mode-only change"
check "git sees it" "$(git -C "$T/install" status --porcelain -- "$F")" " M $F"

echo "update pulls over it"
echo "# upstream change" >> "$T/origin/$F"
g -C "$T/origin" commit -qam "upstream touches the file"
out=$("$T/install/src/zeltro" update 2>&1); rc=$?
check "exit 0" "$rc" "0"
check "reports success" "$(grep -c 'zeltro update completed' <<<"$out")" "1"
check "now at origin" "$(git -C "$T/install" rev-parse HEAD)" "$(git -C "$T/origin" rev-parse HEAD)"
check "upstream change landed" "$(tail -n 1 "$T/install/$F")" "# upstream change"

echo "a pull that really fails"
echo "# local edit" >> "$T/install/$F"
echo "# second upstream change" >> "$T/origin/$F"
g -C "$T/origin" commit -qam "upstream touches it again"
out=$("$T/install/src/zeltro" update 2>&1); rc=$?
check "exit non-zero" "$([ "$rc" -ne 0 ] && echo yes)" "yes"
check "says the pull failed" "$(grep -c 'git pull failed' <<<"$out")" "1"
check "no success line" "$(grep -c 'zeltro update completed' <<<"$out")" "0"
check "local edit kept" "$(tail -n 1 "$T/install/$F")" "# local edit"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
