#!/system/bin/sh
MODDIR=${0%/*}
DATA_DIR=/data/adb/droidspaces-lan-ip

if [ -f "$DATA_DIR/worker.pid" ]; then
    pid=$(cat "$DATA_DIR/worker.pid" 2>/dev/null)
    case "$pid" in
        ''|*[!0-9]*) ;;
        *)
            if [ -r "/proc/$pid/cmdline" ] &&
               tr '\0' ' ' <"/proc/$pid/cmdline" | grep -Fq 'droidspaces-lan-ip/scripts/worker.sh'; then
                kill "$pid" 2>/dev/null || true
            fi
            ;;
    esac
fi
/system/bin/sh "$MODDIR/scripts/api.sh" cleanup >/dev/null 2>&1 || true
rm -rf "$DATA_DIR"
