#!/bin/bash
# Color only on a terminal: no escape codes when stdout is piped, captured or
# redirected, or when NO_COLOR is set to anything. FORCE_COLOR keeps them in a
# pipe. The `zeltro create` menu prints to stderr so the caller's $(...) gets
# just the chosen number. Uses `script` for a real terminal; no network.
#
#   bash tests/no-color.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }

esc() { grep -q $'\033' && echo color || echo plain; }
src() { echo "cd '$REPO/src' && set +u && source scripts/functions.sh 2>/dev/null && source scripts/classify.sh && $1"; }
# A terminal, via script(1): util-linux takes -c, BSD/macOS takes the command last.
tty_run() { # <env assignments> <code>
    if script -qc true /dev/null >/dev/null 2>&1; then
        script -qc "env TERM=xterm-256color $1 bash -c \"$(src "$2")\"" /dev/null
    else
        script -q /dev/null env TERM=xterm-256color $1 bash -c "$(src "$2")"
    fi
}

echo "echo-* helpers"
check "piped: no escape codes" "$(TERM=xterm-256color bash -c "$(src 'echo-red hi')" | esc)" "plain"
F="$(mktemp)"; trap 'rm -f "$F"' EXIT
TERM=xterm-256color bash -c "$(src 'echo-red hi')" > "$F"
check "redirected to a file: none" "$(esc < "$F")" "plain"
check "FORCE_COLOR=1 in a pipe: colored" "$(TERM=xterm-256color FORCE_COLOR=1 bash -c "$(src 'echo-red hi')" | esc)" "color"
check "FORCE_COLOR=0 in a pipe: not" "$(TERM=xterm-256color FORCE_COLOR=0 bash -c "$(src 'echo-red hi')" | esc)" "plain"
if command -v script >/dev/null 2>&1; then
    check "terminal: colored" "$(tty_run "" 'echo-red hi' | esc)" "color"
    check "terminal, NO_COLOR=yes (any value): not" "$(tty_run "NO_COLOR=yes" 'echo-red hi' | esc)" "plain"
    check "terminal, TERM=dumb: not" "$(tty_run "TERM=dumb" 'echo-red hi' | esc)" "plain"
else
    ok "(no script(1): terminal cases skipped)"
fi

echo "zeltro create menu"
idx="$(TERM=xterm-256color bash -c "$(src 'echo 2 | _menu_choose Pick 1 "a|x" "b|y" 2>/dev/null')")"
check "only the choice reaches stdout" "$idx" "2"
shown="$(TERM=xterm-256color bash -c "$(src 'echo 2 | _menu_choose Pick 1 "a|x" "b|y" 2>&1 >/dev/null')")"
check "the menu is still shown (stderr)" "$(printf '%s\n' "$shown" | grep -c '2) b')" "1"
check "no escape codes off a terminal" "$(printf '%s\n' "$shown" | esc)" "plain"

echo "through zeltro"
check "zeltro output piped: no escape codes" "$("$REPO/src/zeltro" ai-unattended 2>&1 | esc)" "plain"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
