#!/system/bin/sh
MODDIR=${0%/*}

# Droidspaces' service script may still be starting containers at boot-completed.
# The worker waits for its daemon process before it touches networking.
/system/bin/sh "$MODDIR/scripts/worker.sh" >/dev/null 2>&1 &
