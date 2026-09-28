#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export DSLI_TEST_STATE="$tmp"
cat >"$tmp/ip" <<'MOCK_IP'
#!/bin/sh
case "$*" in
    '-4 -o addr show dev eth0')
        echo '40: eth0 inet 172.28.204.17/16 scope global eth0'
        echo '40: eth0 inet 192.0.2.111/32 scope global eth0'
        ;;
    '-4 route show dev eth0') echo '192.0.2.0/24 via 172.28.0.1 src 192.0.2.111' ;;
    '-4 route show 192.0.2.111/32') echo '192.0.2.111 via 172.28.204.17 dev ds-br0' ;;
    'neigh show proxy dev wlan0') echo '192.0.2.111 proxy' ;;
    '-4 rule show')
        if [ -f "$DSLI_TEST_STATE/rule" ]; then
            echo '6091: from all to 192.0.2.0/24 lookup main'
        fi
        ;;
    '-4 rule add pref 6091 to 192.0.2.0/24 lookup main')
        [ ! -f "$DSLI_TEST_STATE/rule" ] || exit 1
        : >"$DSLI_TEST_STATE/rule"
        ;;
    '-4 rule del pref 6091 to 192.0.2.0/24 lookup main') rm -f "$DSLI_TEST_STATE/rule" ;;
esac
MOCK_IP
cat >"$tmp/nsenter" <<'MOCK_NSENTER'
#!/bin/sh
shift 4
exec "$@"
MOCK_NSENTER
chmod +x "$tmp/ip" "$tmp/nsenter"
DSLI_IP_BIN=$tmp/ip
DSLI_NSENTER_BIN=$tmp/nsenter
DSLI_DATA_DIR=$tmp/data
. "$root/scripts/lib.sh"

nat_config() { return 0; }
phone_cidr() { echo '192.0.2.102/24'; }
container_pid() { echo 123; }
container_nat_ip() { echo '172.28.204.17'; }

if mapping_active container_one 192.0.2.111 192.0.2.102/24; then
    echo 'Mapping appeared active without an Android LAN policy rule' >&2
    exit 1
fi
apply_mapping container_one 192.0.2.111 192.0.2.102/24
[ -f "$tmp/rule" ] || { echo 'LAN policy rule was not installed' >&2; exit 1; }
mapping_active container_one 192.0.2.111 192.0.2.102/24 || { echo 'Mapping was not active after applying it' >&2; exit 1; }
apply_mapping container_one 192.0.2.111 192.0.2.102/24
mkdir -p "$tmp/data"
printf 'container_two|192.0.2.112|192.0.2.103/24\n' >"$tmp/data/assignments"
remove_lan_rule_if_unused 192.0.2.102/24
[ -f "$tmp/rule" ] || { echo 'Shared LAN policy rule was removed' >&2; exit 1; }
: >"$tmp/data/assignments"
remove_lan_rule_if_unused 192.0.2.102/24
[ ! -f "$tmp/rule" ] || { echo 'Unused LAN policy rule was retained' >&2; exit 1; }
echo 'LAN policy routing tests passed'
