#!/usr/bin/env bash
set -euo pipefail
umask 077
TASK_DIR=/home/karsten/restless-soul-investigation
DEBUG_ROOT="$TASK_DIR/debugger/root"
if pgrep -x worldserver >/dev/null; then
    echo 'A worldserver process is already running. Refusing to start another.' >&2
    exit 1
fi
RUN_DIR=$(mktemp -d "$TASK_DIR/run-XXXXXXXX")
printf '%s\n' "$RUN_DIR" > "$TASK_DIR/current-run"
sha256sum /usr/local/bin/worldserver > "$RUN_DIR/binary.sha256"
cat > "$RUN_DIR/capture.gdb" <<'GDB'
set pagination off
set confirm off
set print thread-events off
set debuginfod enabled off
set auto-load python-scripts off
set print elements 32
run
info program
bt 60
info registers
x/24i $pc-48
thread apply all bt 30
info sharedlibrary
info proc mappings
quit
GDB
cd /
LD_LIBRARY_PATH="$DEBUG_ROOT/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$DEBUG_ROOT/usr/bin/gdb" --data-directory="$DEBUG_ROOT/usr/share/gdb" \
    --batch -x "$RUN_DIR/capture.gdb" --args /usr/local/bin/worldserver \
    2>&1 | tee "$RUN_DIR/console-and-backtrace.log"
