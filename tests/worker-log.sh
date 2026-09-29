#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/module/scripts" "$tmp/data"
cp "$root/scripts/worker.sh" "$tmp/module/scripts/worker.sh"
cat >"$tmp/module/scripts/lib.sh" <<EOF
DATA_DIR=$tmp/data
init_data() { return 0; }
daemon_ready() { return 0; }
EOF
cat >"$tmp/module/scripts/api.sh" <<EOF
#!/bin/sh
printf 'sync called\n' >>'$tmp/data/sync.calls'
EOF

DSLI_WORKER_LOCK_DIR="$tmp/worker.lock" DSLI_SH_BIN=sh timeout 1 sh "$tmp/module/scripts/worker.sh" >/dev/null 2>&1 || :
[ -s "$tmp/data/sync.calls" ] || { echo 'Worker did not sync' >&2; exit 1; }
[ -s "$tmp/data/worker.log" ] || { echo 'Worker log is empty after a successful sync' >&2; exit 1; }
grep -q 'Worker started' "$tmp/data/worker.log"
grep -q 'Sync complete' "$tmp/data/worker.log"
echo 'Worker log test passed'
