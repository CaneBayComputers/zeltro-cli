#!/bin/bash -l
# Installer batch 2 — cassie

mkdir -p /tmp/zeltro-tests/installers2-sessions
LOG=/tmp/zeltro-tests/installers2-master.log
ZELTRO="/usr/local/bin/zeltro"

run_install() {
    local name="$1"
    local logfile="/tmp/zeltro-tests/installers2-sessions/${name}.log"

    echo "[$(date '+%H:%M:%S')] === Starting: $name ===" | tee -a "$LOG"

    TERM=xterm $ZELTRO remove "$name" --force-db-delete > /dev/null 2>&1 || true

    TERM=xterm $ZELTRO install "$name" > "$logfile" 2>&1
    local code=$?
    echo "EXIT:$code" >> "$logfile"

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${name}/" 2>/dev/null)
    echo "[$(date '+%H:%M:%S')] DONE: $name | exit=$code | HTTP $http_code" | tee -a "$LOG"
}

echo "=== Installer Batch 2 (cassie) — $(date) ===" | tee "$LOG"
echo ""

run_install "photoprism"
run_install "immich"
run_install "triliumnext"
run_install "searxng"
run_install "glances"
run_install "wger"
run_install "mattermost"
run_install "outline"

echo "" | tee -a "$LOG"
echo "=== ALL DONE — $(date) ===" | tee -a "$LOG"
