#!/bin/bash
# Inside WSL, Windows' PATH is appended (/mnt/c/...), so Windows' npm or a
# Windows install of an agent could be found ahead of, or instead of, Linux
# ones. functions.sh moves those entries last, never counts a /mnt/<drive>
# binary as installed, and `npm install -g` uses Linux npm by absolute path
# (also under sudo, whose secure_path lacks nvm). Fakes /mnt/c with a tmpfs in
# a private mount namespace (`unshare -rm`); no network, no real installs.
#
#   bash tests/wsl-path.sh
set -u

if [ "${ZELTRO_WSL_TEST_NS:-}" != "1" ]; then
    if ! unshare -rm true 2>/dev/null; then
        echo "skipped: needs unshare -rm (Linux user namespaces)"; exit 0
    fi
    exec env ZELTRO_WSL_TEST_NS=1 unshare -rm bash "$0" "$@"
fi
mount -t tmpfs none /mnt || { echo "FAIL: couldn't mount a tmpfs on /mnt"; exit 1; }
unset NVM_DIR

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }

WIN_NODE="/mnt/c/Program Files/nodejs"
WIN_NPM_GLOBAL="/mnt/c/Users/shawn/AppData/Roaming/npm"
NVM_BIN="$T/home/.nvm/versions/node/v24.22.1/bin"
mkdir -p "$WIN_NODE" "$WIN_NPM_GLOBAL" "$NVM_BIN" "$T/home/.nvm/alias" "$T/bin" "$T/sys"
echo 24 > "$T/home/.nvm/alias/default"

# Windows' npm and codex: running either is a test failure.
for f in "$WIN_NODE/npm" "$WIN_NODE/node" "$WIN_NPM_GLOBAL/codex"; do
    printf '#!/bin/sh\necho "$0 $*" >> "%s/windows-ran"\n' "$T" > "$f"; chmod +x "$f"
done
# Linux npm: `prefix -g` answers $FAKE_PREFIX, `install` is logged.
cat > "$NVM_BIN/npm" <<FAKE
#!/bin/sh
if [ "\$1" = "prefix" ]; then echo "\${FAKE_PREFIX:-$T/home/.nvm/versions/node/v24.22.1}"; exit 0; fi
echo "\$0 \$*" >> "$T/npm-ran"
FAKE
printf '#!/bin/sh\necho v24.22.1\n' > "$NVM_BIN/node"
chmod +x "$NVM_BIN/npm" "$NVM_BIN/node"
mkdir -p "$T/home/.nvm/versions/node/v24.22.1/lib/node_modules"
# sudo: `-n true` succeeds; anything else is logged, not run.
cat > "$T/sys/sudo" <<FAKE
#!/bin/sh
[ "\$*" = "-n true" ] && exit 0
printf '%s\n' "\$@" > "$T/sudo-ran"
FAKE
chmod +x "$T/sys/sudo"

# The app's non-interactive shell: no nvm, Windows' PATH appended.
BASE_PATH="/usr/bin:/bin:$WIN_NODE:$WIN_NPM_GLOBAL:/mnt/c/Windows/system32"

fn() { # <PATH> <commands...>: run in a clean subshell with functions.sh sourced
    local p="$1"; shift
    ( export HOME="$T/home" PATH="$p"; unset NPM_CONFIG_PREFIX npm_config_prefix
      cd "$REPO/src" && set +u && source scripts/functions.sh >/dev/null 2>&1
      eval "$@" )
}

echo "PATH order"
check "nvm's npm wins over Windows' npm" "$(fn "$BASE_PATH" 'command -v npm')" "$NVM_BIN/npm"
check "nvm's node wins over Windows' node" "$(fn "$BASE_PATH" 'command -v node')" "$NVM_BIN/node"
check "Windows entries kept, after the Linux ones" \
    "$(fn "$BASE_PATH" 'echo "$PATH"')" "/usr/bin:/bin:$NVM_BIN:$WIN_NODE:$WIN_NPM_GLOBAL:/mnt/c/Windows/system32"
check "no /mnt entries: PATH untouched apart from the agent dirs" \
    "$(fn "/usr/bin:/bin" 'echo "$PATH"')" "/usr/bin:/bin:$NVM_BIN"
check "NVM_DIR honoured" \
    "$(mv "$T/home/.nvm" "$T/nvm-elsewhere"; ( export NVM_DIR="$T/nvm-elsewhere"; fn "$BASE_PATH" 'command -v npm' ); mv "$T/nvm-elsewhere" "$T/home/.nvm")" \
    "$T/nvm-elsewhere/versions/node/v24.22.1/bin/npm"

echo "Windows binaries never count"
check "zeltro_host_cmd skips a /mnt/c npm (path with a space)" \
    "$(mv "$T/home/.nvm" "$T/nvm-off"; fn "$BASE_PATH" 'zeltro_host_cmd npm; echo "rc=$?"'; mv "$T/nvm-off" "$T/home/.nvm")" "rc=1"
check "a Windows codex isn't an installed agent" "$(fn "$BASE_PATH" 'zeltro_agent_installed codex && echo yes || echo no')" "no"
check "ai_auth.py agrees" \
    "$(HOME="$T/home" PATH="$BASE_PATH" python3 -c "import sys; sys.path.insert(0, '$REPO/src/scripts'); import ai_auth; print(ai_auth.installed('codex'))")" "False"
printf '#!/bin/sh\necho codex-cli 0.128.0\n' > "$NVM_BIN/codex"; chmod +x "$NVM_BIN/codex"
check "a Linux codex is" "$(fn "$BASE_PATH" 'zeltro_agent_installed codex && echo yes || echo no')" "yes"
check "ai_auth.py finds the Linux one (PATH as the dispatcher passes it)" \
    "$(HOME="$T/home" PATH="$BASE_PATH:$NVM_BIN" python3 -c "import sys; sys.path.insert(0, '$REPO/src/scripts'); import ai_auth; print(ai_auth.which('codex'))")" "$NVM_BIN/codex"
rm -f "$NVM_BIN/codex"

echo "npm install -g"
rm -f "$T/npm-ran"
fn "$BASE_PATH" '_npm_install_global @openai/codex' >/dev/null 2>&1
check "writable nvm prefix: Linux npm installs directly" "$(cat "$T/npm-ran" 2>/dev/null)" "$NVM_BIN/npm install -g @openai/codex"

rm -f "$T/npm-ran" "$T/sudo-ran"
FAKE_PREFIX=/usr fn "$T/sys:$BASE_PATH" '_npm_install_global @openai/codex' >/dev/null 2>&1
check "unwritable prefix: sudo gets npm by path and this PATH" "$(tr '\n' ' ' < "$T/sudo-ran" 2>/dev/null)" \
    "-n env PATH=$T/sys:/usr/bin:/bin:$NVM_BIN:$WIN_NODE:$WIN_NPM_GLOBAL:/mnt/c/Windows/system32 $NVM_BIN/npm install -g @openai/codex "

# curl: offline (exit 7), or serving a fake nvm whose `nvm install` makes a
# Node whose npm logs what it installs.
mkdir -p "$T/offline" "$T/online"
printf '#!/bin/sh\nexit 7\n' > "$T/offline/curl"
cat > "$T/online/curl" <<FAKE
#!/bin/sh
case "\$*" in
    *api.github.com*) echo '{"tag_name": "v0.40.9"}' ;;
    *nvm-sh/nvm/v0.40.9/install.sh*) cat <<'EOS'
mkdir -p "\$NVM_DIR"
cat > "\$NVM_DIR/nvm.sh" <<'EON'
nvm() {
    case "\$1" in
        install) b="\$NVM_DIR/versions/node/v24.0.0/bin"; mkdir -p "\$b" "\$NVM_DIR/versions/node/v24.0.0/lib/node_modules"
                 printf '#!/bin/sh\necho v24.0.0\n' > "\$b/node"
                 printf '#!/bin/sh\n[ "\$1" = prefix ] && { echo "%s"; exit 0; }\necho "\$0 \$*" >> "%s"\n' "\$NVM_DIR/versions/node/v24.0.0" "\$NVM_DIR/../npm-ran" > "\$b/npm"
                 chmod +x "\$b/node" "\$b/npm" ;;
        alias) mkdir -p "\$NVM_DIR/alias"; echo "\$3" > "\$NVM_DIR/alias/default" ;;
    esac
}
EON
EOS
    ;;
    *) exit 22 ;;
esac
FAKE
chmod +x "$T/offline/curl" "$T/online/curl"

mv "$T/home/.nvm" "$T/nvm-off"
out="$(fn "$T/offline:$BASE_PATH" '_npm_install_global @openai/codex; echo "rc=$?"' 2>&1)"
check "only Windows' npm: fails" "$(echo "$out" | grep -o 'rc=[0-9]*')" "rc=1"
check "and says Linux has no Node.js" "$(echo "$out" | grep -c "isn't installed in Linux")" "1"
check "and nothing half-installed is left as Node" "$(ls "$T/home/.nvm/versions" 2>/dev/null)" ""

echo "no Linux Node at all: installed for this user"
rm -rf "$T/home/.nvm"
out="$(fn "$T/online:$BASE_PATH" '_npm_install_global @openai/codex; echo "rc=$?"; command -v npm' 2>&1)"
check "succeeds" "$(echo "$out" | grep -o 'rc=[0-9]*')" "rc=0"
check "through the new nvm Node's npm" "$(cat "$T/home/npm-ran" 2>/dev/null)" "$T/home/.nvm/versions/node/v24.0.0/bin/npm install -g @openai/codex"
check "which now wins on PATH" "$(echo "$out" | tail -n 1)" "$T/home/.nvm/versions/node/v24.0.0/bin/npm"
rm -rf "$T/home/.nvm"; mv "$T/nvm-off" "$T/home/.nvm"
check "Windows' npm and codex were never run" "$(cat "$T/windows-ran" 2>/dev/null)" ""

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
