#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/containers/container_one" "$tmp/containers/container_two" "$tmp/containers/host_container" "$tmp/bin"
printf 'name=container_one\nnet_mode=nat\n' >"$tmp/containers/container_one/container.config"
printf 'name=container_two\nnet_mode=nat\n' >"$tmp/containers/container_two/container.config"
printf 'name=host_container\nnet_mode=host\n' >"$tmp/containers/host_container/container.config"
cat >"$tmp/bin/ip" <<'EOF'
#!/bin/sh
if [ "$*" = '-4 -o addr show dev wlan0' ]; then
    echo '7: wlan0    inet 192.0.2.102/24 brd 192.0.2.255 scope global wlan0'
fi
EOF
cat >"$tmp/bin/droidspaces" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$tmp/bin/ip" "$tmp/bin/droidspaces"
export DSLI_DATA_DIR="$tmp/data"
export DSLI_CONTAINERS_DIR="$tmp/containers"
export DSLI_DROID_MODULE_DIR="$tmp/no-module"
export DSLI_DROID_BIN="$tmp/bin/droidspaces"
export DSLI_IP_BIN="$tmp/bin/ip"
api=$root/scripts/api.sh

list=$(sh "$api" list)
printf '%s\n' "$list" | grep -q '^CONTAINER|container_one|'
printf '%s\n' "$list" | grep -q '^CONTAINER|container_two|'
if printf '%s\n' "$list" | grep -q '^CONTAINER|host_container|'; then
    echo 'Host-mode container was listed' >&2
    exit 1
fi

sh "$api" set container_one 192.0.2.240 >/dev/null
grep -qx 'container_one|192.0.2.240|192.0.2.102/24' "$tmp/data/assignments"
list=$(sh "$api" list)
printf '%s\n' "$list" | grep -qx 'CONTAINER|container_one||192.0.2.240|192.0.2.102/24|stopped'
if sh "$api" set container_two 192.0.2.240 >"$tmp/result" 2>&1; then
    echo 'Duplicate address was accepted' >&2
    exit 1
fi
if sh "$api" set container_two 198.51.100.240 >"$tmp/result" 2>&1; then
    echo 'Address on another subnet was accepted' >&2
    exit 1
fi
if sh "$api" set container_two 192.0.2.102 >"$tmp/result" 2>&1; then
    echo 'Phone address was accepted' >&2
    exit 1
fi
if sh "$api" set container_two 192.0.2.241. >"$tmp/result" 2>&1; then
    echo 'Malformed address was accepted' >&2
    exit 1
fi
if sh "$api" set host_container 192.0.2.241 >"$tmp/result" 2>&1; then
    echo 'Host-mode container was assigned' >&2
    exit 1
fi

sh "$api" set container_one 192.0.2.241 >/dev/null
grep -qx 'container_one|192.0.2.241|192.0.2.102/24' "$tmp/data/assignments"
list=$(sh "$api" list)
printf '%s\n' "$list" | grep -qx 'CONTAINER|container_one||192.0.2.241|192.0.2.102/24|stopped'
if grep -q '192.0.2.240' "$tmp/data/assignments"; then
    echo 'Old address remained saved' >&2
    exit 1
fi
sh "$api" delete container_one >/dev/null
if [ -s "$tmp/data/assignments" ]; then
    echo 'Deleted address remained saved' >&2
    exit 1
fi
echo 'API configuration tests passed'
