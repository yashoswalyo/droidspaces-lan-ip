#!/system/bin/sh
MODDIR=${0%/*}/..
. "$MODDIR/scripts/lib.sh"

init_data || exit 1
LOCK=${DSLI_WORKER_LOCK_DIR:-/dev/.droidspaces-lan-ip-worker.lock}
SH_BIN=${DSLI_SH_BIN:-/system/bin/sh}
mkdir "$LOCK" 2>/dev/null || exit 0
printf '%s\n' "$$" >"$DATA_DIR/worker.pid"
trap 'rm -f "$DATA_DIR/worker.pid"; rmdir "$LOCK" 2>/dev/null' EXIT
trap 'exit 0' INT TERM

log_event() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$DATA_DIR/worker.log"
}

sync_mappings() {
    if "$SH_BIN" "$MODDIR/scripts/api.sh" sync >>"$DATA_DIR/worker.log" 2>&1; then
        syncs_since_log=$((syncs_since_log + 1))
        if [ "$log_next_sync" = 1 ] || [ "$syncs_since_log" -ge 60 ]; then
            log_event 'Sync complete'
            log_next_sync=0
            syncs_since_log=0
        fi
    else
        status=$?
        log_event "Sync failed (exit status $status)"
    fi
}

log_event 'Worker started'
started=0
daemon_state=unknown
log_next_sync=1
syncs_since_log=0
while :; do
    if daemon_ready; then
        if [ "$daemon_state" != ready ]; then
            log_event 'Droidspaces daemon ready'
            daemon_state=ready
            log_next_sync=1
        fi
        started=1
        sync_mappings
    else
        if [ "$daemon_state" != waiting ]; then
            log_event 'Waiting for Droidspaces daemon'
            daemon_state=waiting
            log_next_sync=1
        fi
        if [ "$started" = 1 ]; then sync_mappings; fi
    fi
    sleep 15
done
