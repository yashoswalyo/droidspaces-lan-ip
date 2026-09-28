#!/system/bin/sh
MODDIR=${0%/*}/..
. "$MODDIR/scripts/lib.sh"

init_data || exit 1
LOCK=/dev/.droidspaces-lan-ip-worker.lock
mkdir "$LOCK" 2>/dev/null || exit 0
printf '%s\n' "$$" >"$DATA_DIR/worker.pid"
trap 'rm -f "$DATA_DIR/worker.pid"; rmdir "$LOCK" 2>/dev/null' EXIT
trap 'exit 0' INT TERM

started=0
while :; do
    if daemon_ready; then
        started=1
        /system/bin/sh "$MODDIR/scripts/api.sh" sync >>"$DATA_DIR/worker.log" 2>&1
    elif [ "$started" = 1 ]; then
        /system/bin/sh "$MODDIR/scripts/api.sh" sync >>"$DATA_DIR/worker.log" 2>&1
    fi
    sleep 15
done
