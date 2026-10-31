#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run through sudo in your server terminal.' >&2; exit 1; }
TASK_DIR=/home/karsten/restless-soul-investigation
SERVER=/usr/local/bin/worldserver
CANDIDATE="$TASK_DIR/worldserver.fixed"
BASELINE=443c8a17fea72c8f5096cda2f0f617de5ad339817aed93386b79c79807003197
FIXED=c5c77245b848c28061d49ce68734938b935093665c682e34a9f409f7f5900eff
if pgrep -x worldserver >/dev/null; then
    echo 'Worldserver is running. Refusing replacement; no process was stopped.' >&2
    exit 1
fi
[[ $(sha256sum "$SERVER" | cut -d ' ' -f1) == "$BASELINE" ]] || { echo 'Unexpected installed baseline.' >&2; exit 1; }
[[ $(sha256sum "$CANDIDATE" | cut -d ' ' -f1) == "$FIXED" ]] || { echo 'Candidate checksum mismatch.' >&2; exit 1; }
ldd "$CANDIDATE" > "$TASK_DIR/fixed-libraries.txt"
if grep -q 'not found' "$TASK_DIR/fixed-libraries.txt"; then echo 'Missing runtime library.' >&2; exit 1; fi
BACKUP=$(mktemp -d /home/karsten/acore-backups/autobalance-before-XXXXXXXX)
cp -p "$SERVER" "$BACKUP/worldserver"
STAGED=$(mktemp /usr/local/bin/.worldserver-autobalance-XXXXXXXX)
trap 'rm -f "$STAGED"' EXIT
install -o root -g root -m 0755 "$CANDIDATE" "$STAGED"
mv -f "$STAGED" "$SERVER"
start_debug() {
    runuser -u karsten -- tmux kill-session -t worldserver 2>/dev/null || true
    runuser -u karsten -- tmux new-session -d -c / -s worldserver "$TASK_DIR/run-worldserver-debug.sh"
}
if ! start_debug; then
    cp -p "$BACKUP/worldserver" "$SERVER"
    echo "Could not start diagnostic session; restored original binary. Backup: $BACKUP" >&2
    exit 1
fi
sleep 10
if ! pgrep -u karsten -x worldserver >/dev/null; then
    cp -p "$BACKUP/worldserver" "$SERVER"
    start_debug || true
    echo "Candidate exited during startup; restored original binary. Backup: $BACKUP" >&2
    exit 1
fi
echo 'AutoBalance fix installed; worldserver running under the debugger for confirmation.'
echo 'Authserver, addon, database and configuration were not changed.'
echo "Rollback backup: $BACKUP"
