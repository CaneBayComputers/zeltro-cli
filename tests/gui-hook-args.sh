#!/bin/bash
# Regression test: zeltro_gui_hook_args (and the other functions that locate the
# Zeltro checkout) must work after the caller has changed directory.
#
# 2026-09-28: resume.sh and ai.sh source functions.sh by a RELATIVE path, then cd
# into the project. zeltro_gui_hook_args resolved "${BASH_SOURCE[0]}" at call
# time, got /zeltro, and under `set -e` killed `zeltro resume` with exit 1 and no
# message for every session the GUI started (ZELTRO_GUI_SESSION set).
#
#   bash tests/gui-hook-args.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }

# Like resume.sh: cd to src/, source by a relative path, cd somewhere else, then
# call the function with `set -e` on. Prints the hook args, one per line.
hook_args() { # <agent>
    ( cd "$REPO/src" && set +u && NO_COLOR=1 source scripts/functions.sh >/dev/null 2>&1
      cd "$T"
      set -e
      ZELTRO_GUI_SESSION=test-session CODEX_HOME="$T/codex" zeltro_gui_hook_args "$1"
      printf '%s\n' "${ZELTRO_GUI_HOOK_ARGS[@]+"${ZELTRO_GUI_HOOK_ARGS[@]}"}"
      echo "__REACHED__" )
}

ZELTRO="$REPO/src/zeltro"
for agent in claude codex aider; do
    out="$(hook_args "$agent")"; code=$?
    [ "$code" = 0 ] && echo "$out" | grep -q __REACHED__ && ok "$agent: returns normally after a cd (set -e)" \
        || bad "$agent: aborted (exit $code)"
    echo "$out" | grep -qF "$ZELTRO" && ok "$agent: hook uses the absolute zeltro path" \
        || bad "$agent: no absolute path in: $(echo "$out" | tr '\n' ' ')"
    echo "$out" | grep -qE '(^|[" ])/zeltro gui' && bad "$agent: hook points at /zeltro" || ok "$agent: no bare /zeltro"
done

out="$( cd "$REPO/src" && set +u && source scripts/functions.sh >/dev/null 2>&1; cd "$T"; set -e
        unset ZELTRO_GUI_SESSION; zeltro_gui_hook_args claude; echo "n=${#ZELTRO_GUI_HOOK_ARGS[@]}" )"
[ "$out" = "n=0" ] && ok "no hooks without ZELTRO_GUI_SESSION" || bad "hooks added outside the app: $out"

src="$( cd "$REPO/src" && set +u && source scripts/functions.sh >/dev/null 2>&1; cd "$T"; echo "$ZELTRO_SRC_DIR" )"
[ "$src" = "$REPO/src" ] && ok "ZELTRO_SRC_DIR resolved at source time" || bad "ZELTRO_SRC_DIR='$src'"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
