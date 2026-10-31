#!/usr/bin/env bash
# Explicit operator entry point. No installation is performed by tests or CI.
set -euo pipefail
if [[ ${1:-} != --deploy ]]; then
    echo 'Usage: sudo bash scripts/deploy-local.sh --deploy' >&2
    exit 2
fi
if [[ $EUID != 0 ]]; then
    echo 'Root privileges are required. Run this script through sudo in your server terminal.' >&2
    exit 1
fi
TASK_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SERVER=/usr/local/bin/worldserver
CONFIG=/usr/local/etc/modules/MultiBotBridge.conf
SERVER_USER=karsten
EXPECTED_BASELINE=3848d0a3530bebdf7a8d0085b2a2f4d84415cf57e0e22fee6530de64baff696d
EXPECTED_CANDIDATE=443c8a17fea72c8f5096cda2f0f617de5ad339817aed93386b79c79807003197
TMUX=$(command -v tmux)
RUNUSER=$(command -v runuser)
SERVER_UID=$(id -u "$SERVER_USER")
tmux_user() { "$RUNUSER" -u "$SERVER_USER" -- "$TMUX" "$@"; }
server_alive() { pgrep -u "$SERVER_UID" -x worldserver >/dev/null; }
start_server() {
    tmux_user kill-session -t worldserver 2>/dev/null || true
    tmux_user new-session -d -c / -s worldserver "$SERVER"
}
cd "$TASK_ROOT"
sha256sum -c dist/SHA256SUMS
[[ $(sha256sum "$SERVER" | cut -d ' ' -f1) == "$EXPECTED_BASELINE" ]] || {
    echo 'Installed server differs from the verified baseline. Nothing changed.' >&2
    exit 1
}
[[ -f "$CONFIG" && ! -L "$CONFIG" ]] || { echo 'Unexpected module config path.' >&2; exit 1; }
tmux_user has-session -t worldserver
server_alive || { echo 'Expected worldserver process is missing.' >&2; exit 1; }
AUTH_PID=$(pgrep -u "$SERVER_UID" -x authserver || true)
BACKUP=$(mktemp -d /home/karsten/acore-backups/random-bot-before-XXXXXXXX)
cp -p "$SERVER" "$BACKUP/worldserver"
cp -p "$CONFIG" "$BACKUP/MultiBotBridge.conf"
STAGED_SERVER=$(mktemp /usr/local/bin/.worldserver-random-bot-XXXXXXXX)
STAGED_CONFIG=$(mktemp /usr/local/etc/modules/.MultiBotBridge-random-bot-XXXXXXXX)
STOPPED=0
INSTALLED=0
cleanup() {
    local result=$?
    trap - EXIT
    rm -f "$STAGED_SERVER" "$STAGED_CONFIG"
    if (( result != 0 && STOPPED == 1 )); then
        if ! server_alive; then
            echo 'Deployment failed after shutdown. Restoring the original server and configuration.' >&2
            if (( INSTALLED == 1 )); then
                cp -p "$BACKUP/worldserver" "$SERVER"
                cp -p "$BACKUP/MultiBotBridge.conf" "$CONFIG"
            fi
            start_server || true
        else
            echo 'Server is still running; no automatic stop will be attempted.' >&2
        fi
    fi
    echo "Rollback backup: $BACKUP"
    exit "$result"
}
trap cleanup EXIT
gzip -dc dist/worldserver-linux-x86_64.gz > "$STAGED_SERVER"
[[ $(sha256sum "$STAGED_SERVER" | cut -d ' ' -f1) == "$EXPECTED_CANDIDATE" ]]
chmod 0755 "$STAGED_SERVER"
ldd "$STAGED_SERVER" > "$BACKUP/candidate-libraries.txt"
if grep -q 'not found' "$BACKUP/candidate-libraries.txt"; then
    echo 'Missing candidate runtime libraries. Nothing changed.' >&2
    exit 1
fi
python3 - "$CONFIG" "$STAGED_CONFIG" <<'PY'
from pathlib import Path
import re
import sys
source = Path(sys.argv[1]).read_text()
source = re.sub(r'^\s*MultiBotBridge\.RandomBotDirectory\.Enable\s*=.*\n?', '', source, flags=re.MULTILINE)
Path(sys.argv[2]).write_text(source.rstrip() + '\n\nMultiBotBridge.RandomBotDirectory.Enable = 1\n')
PY
chown --reference="$CONFIG" "$STAGED_CONFIG"
chmod --reference="$CONFIG" "$STAGED_CONFIG"
echo 'Preflight complete. Requesting graceful worldserver shutdown in 10 seconds.'
tmux_user send-keys -t worldserver 'server shutdown 10' Enter
for (( attempt=0; attempt<120; attempt++ )); do
    if ! server_alive; then STOPPED=1; break; fi
    sleep 1
done
if (( STOPPED != 1 )); then
    echo 'Worldserver did not stop. Installation canceled; no forced termination.' >&2
    exit 1
fi
# Mark the replacement phase before either rename, so partial installation can be rolled back.
INSTALLED=1
mv -f "$STAGED_SERVER" "$SERVER"
mv -f "$STAGED_CONFIG" "$CONFIG"
start_server
sleep 10
server_alive || { echo 'Candidate exited during startup.' >&2; exit 1; }
[[ $(pgrep -u "$SERVER_UID" -x authserver || true) == "$AUTH_PID" ]] || {
    echo 'Authserver process changed unexpectedly; inspect the stack.' >&2
    exit 1
}
tmux_user capture-pane -p -t worldserver:0 -S -100 > "$BACKUP/startup-console.txt"
sha256sum "$SERVER" > "$BACKUP/installed-worldserver.sha256"
printf '%s\n' "$BACKUP" > /home/karsten/random-bot-release/last-deployment-backup.txt
chown "$SERVER_USER:$SERVER_USER" /home/karsten/random-bot-release/last-deployment-backup.txt
echo 'Candidate installed and process running. Verify startup completion and test the addon in-game.'
echo 'Authserver was not restarted. No database changes were introduced by this feature.'
