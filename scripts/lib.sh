#!/system/bin/sh

DATA_DIR=${DSLI_DATA_DIR:-/data/adb/droidspaces-lan-ip}
CONTAINERS_DIR=${DSLI_CONTAINERS_DIR:-/data/local/Droidspaces/Containers}
DROID_MODULE_DIR=${DSLI_DROID_MODULE_DIR:-/data/adb/modules/droidspaces}
DROID_BIN=${DSLI_DROID_BIN:-/data/local/Droidspaces/bin/droidspaces}
IP_BIN=${DSLI_IP_BIN:-/system/bin/ip}
NSENTER_BIN=${DSLI_NSENTER_BIN:-/system/bin/nsenter}
PGREP_BIN=${DSLI_PGREP_BIN:-/system/bin/pgrep}
UPLINK=${DSLI_UPLINK:-wlan0}
BRIDGE=${DSLI_BRIDGE:-ds-br0}
NAT_GATEWAY=${DSLI_NAT_GATEWAY:-172.28.0.1}
LAN_RULE_PRIORITY=6091
DB=$DATA_DIR/assignments

init_data() {
    umask 077
    mkdir -p "$DATA_DIR" || return 1
    [ -f "$DB" ] || : >"$DB"
    chmod 600 "$DB" 2>/dev/null || true
}

valid_name() {
    case "$1" in
        ''|*[!a-zA-Z0-9_.-]*) return 1 ;;
        *) return 0 ;;
    esac
}

ip_to_u32() (
    case "$1" in
        ''|*[!0-9.]*|.*|*..*|*.) return 1 ;;
    esac
    old_ifs=$IFS
    IFS=.
    # Input is checked below before arithmetic; field splitting is intentional.
    set -- $1
    IFS=$old_ifs
    [ "$#" -eq 4 ] || return 1
    number=0
    for octet do
        case "$octet" in
            ''|*[!0-9]*|0[0-9]*) return 1 ;;
        esac
        [ "$octet" -le 255 ] || return 1
        number=$((number * 256 + octet))
    done
    printf '%s\n' "$number"
)

phone_cidr() {
    "$IP_BIN" -4 -o addr show dev "$UPLINK" 2>/dev/null |
        awk '$3 == "inet" { print $4; exit }'
}

ip_on_phone_lan() {
    target=$1
    cidr=$2
    case "$cidr" in
        */*) ;;
        *) return 1 ;;
    esac
    host=${cidr%/*}
    prefix=${cidr#*/}
    case "$prefix" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$prefix" -ge 1 ] && [ "$prefix" -le 30 ] || return 1
    target_n=$(ip_to_u32 "$target") || return 1
    host_n=$(ip_to_u32 "$host") || return 1
    mask=$(( (4294967295 << (32 - prefix)) & 4294967295 ))
    network=$((host_n & mask))
    broadcast=$((network | (4294967295 ^ mask)))
    [ "$((target_n & mask))" -eq "$network" ] &&
        [ "$target_n" -ne "$host_n" ] &&
        [ "$target_n" -ne "$network" ] &&
        [ "$target_n" -ne "$broadcast" ]
}

cidr_subnet() (
    cidr=$1
    case "$cidr" in
        */*) ;;
        *) return 1 ;;
    esac
    host=${cidr%/*}
    prefix=${cidr#*/}
    case "$prefix" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$prefix" -ge 1 ] && [ "$prefix" -le 30 ] || return 1
    host_n=$(ip_to_u32 "$host") || return 1
    mask=$(( (4294967295 << (32 - prefix)) & 4294967295 ))
    network=$((host_n & mask))
    printf '%s.%s.%s.%s/%s\n' \
        "$(( (network >> 24) & 255 ))" "$(( (network >> 16) & 255 ))" \
        "$(( (network >> 8) & 255 ))" "$(( network & 255 ))" "$prefix"
)

lan_rule_present() (
    subnet=$1
    "$IP_BIN" -4 rule show 2>/dev/null |
        awk -v priority="$LAN_RULE_PRIORITY:" -v subnet="$subnet" \
            '$1 == priority && $2 == "from" && $3 == "all" && $4 == "to" && $5 == subnet && $6 == "lookup" && $7 == "main" { found=1 } END { exit !found }'
)

ensure_lan_rule() (
    subnet=$1
    lan_rule_present "$subnet" || "$IP_BIN" -4 rule add pref "$LAN_RULE_PRIORITY" to "$subnet" lookup main
)

remove_lan_rule() (
    subnet=$(cidr_subnet "$1") || return 0
    lan_rule_present "$subnet" || return 0
    "$IP_BIN" -4 rule del pref "$LAN_RULE_PRIORITY" to "$subnet" lookup main 2>/dev/null || true
)

remove_lan_rule_if_unused() (
    subnet=$(cidr_subnet "$1") || return 0
    while IFS='|' read -r name lan_ip bound_cidr; do
        [ "$(cidr_subnet "$bound_cidr")" = "$subnet" ] && return 0
    done <"$DB"
    remove_lan_rule "$1"
)

daemon_ready() {
    [ -f "$DROID_MODULE_DIR/module.prop" ] || return 1
    [ ! -e "$DROID_MODULE_DIR/disable" ] || return 1
    [ -x "$DROID_BIN" ] || return 1
    "$PGREP_BIN" -f 'droidspaces daemon' >/dev/null 2>&1
}

cfg_value() (
    key=$1
    file=$2
    sed -n "s/^$key=//p" "$file" | head -n 1
)

nat_config() (
    wanted=$1
    for cfg in "$CONTAINERS_DIR"/*/container.config; do
        [ -f "$cfg" ] || continue
        name=$(cfg_value name "$cfg")
        valid_name "$name" || continue
        [ "$name" = "$wanted" ] || continue
        [ "$(cfg_value net_mode "$cfg")" = nat ] || return 1
        printf '%s\n' "$cfg"
        return 0
    done
    return 1
)

assignment() {
    awk -F '|' -v wanted="$1" '$1 == wanted { print $2 "|" $3; exit }' "$DB"
}

assignment_owner() {
    awk -F '|' -v wanted="$1" '$2 == wanted { print $1; exit }' "$DB"
}

container_pid() (
    pid=$("$DROID_BIN" --name="$1" pid 2>/dev/null)
    case "$pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ -d "/proc/$pid" ] || return 1
    [ "$(readlink "/proc/$pid/ns/net")" != "$(readlink /proc/1/ns/net)" ] || return 1
    printf '%s\n' "$pid"
)

container_nat_ip() {
    "$NSENTER_BIN" -t "$1" -n -- "$IP_BIN" -4 -o addr show dev eth0 2>/dev/null |
        awk '$4 ~ /^172\.28\./ { sub(/\/.*/, "", $4); print $4; exit }'
}

proxy_present() {
    "$IP_BIN" neigh show proxy dev "$UPLINK" 2>/dev/null |
        awk -v wanted="$1" '$1 == wanted { found=1 } END { exit !found }'
}

mapping_active() (
    name=$1
    lan_ip=$2
    subnet=$(cidr_subnet "$3") || return 1
    lan_rule_present "$subnet" || return 1
    pid=$(container_pid "$name") || return 1
    nat_ip=$(container_nat_ip "$pid")
    [ -n "$nat_ip" ] || return 1
    "$NSENTER_BIN" -t "$pid" -n -- "$IP_BIN" -4 -o addr show dev eth0 2>/dev/null |
        grep -Fq "inet $lan_ip/32 " || return 1
    "$NSENTER_BIN" -t "$pid" -n -- "$IP_BIN" -4 route show dev eth0 2>/dev/null |
        grep -Fq "src $lan_ip" || return 1
    "$IP_BIN" -4 route show "$lan_ip/32" 2>/dev/null |
        grep -Fq "via $nat_ip dev $BRIDGE" || return 1
    proxy_present "$lan_ip"
)

remove_mapping() (
    name=$1
    lan_ip=$2
    pid=$(container_pid "$name")
    if [ -n "$pid" ]; then
        route=$("$NSENTER_BIN" -t "$pid" -n -- "$IP_BIN" -4 route show dev eth0 2>/dev/null |
            awk -v wanted="$lan_ip" '{ for (i=1; i<NF; i++) if ($i == "src" && $(i+1) == wanted) { print $1; exit } }')
        [ -z "$route" ] || "$NSENTER_BIN" -t "$pid" -n -- "$IP_BIN" route del "$route" dev eth0 2>/dev/null
        "$NSENTER_BIN" -t "$pid" -n -- "$IP_BIN" addr del "$lan_ip/32" dev eth0 2>/dev/null || true
    fi
    if "$IP_BIN" -4 route show "$lan_ip/32" 2>/dev/null | grep -Fq "dev $BRIDGE"; then
        "$IP_BIN" route del "$lan_ip/32" dev "$BRIDGE" 2>/dev/null || true
    fi
    "$IP_BIN" neigh del proxy "$lan_ip" dev "$UPLINK" 2>/dev/null || true
)

apply_mapping() (
    name=$1
    lan_ip=$2
    saved_cidr=$3
    nat_config "$name" >/dev/null || { remove_mapping "$name" "$lan_ip"; return 0; }
    [ "$(phone_cidr)" = "$saved_cidr" ] || { remove_mapping "$name" "$lan_ip"; return 0; }
    ip_on_phone_lan "$lan_ip" "$saved_cidr" || { remove_mapping "$name" "$lan_ip"; return 0; }
    pid=$(container_pid "$name") || { remove_mapping "$name" "$lan_ip"; return 0; }
    nat_ip=$(container_nat_ip "$pid")
    case "$nat_ip" in
        172.28.*) ;;
        *) remove_mapping "$name" "$lan_ip"; return 0 ;;
    esac
    existing_route=$("$IP_BIN" -4 route show "$lan_ip/32" 2>/dev/null)
    case "$existing_route" in
        ''|*"via $nat_ip dev $BRIDGE"*) ;;
        *) printf 'Refusing to replace another host route for %s\n' "$lan_ip" >&2; return 1 ;;
    esac
    if ! "$NSENTER_BIN" -t "$pid" -n -- "$IP_BIN" -4 -o addr show dev eth0 |
        grep -Fq "inet $lan_ip/32 "; then
        "$NSENTER_BIN" -t "$pid" -n -- "$IP_BIN" addr add "$lan_ip/32" dev eth0 || return 1
    fi
    subnet=$(cidr_subnet "$saved_cidr") || return 1
    "$NSENTER_BIN" -t "$pid" -n -- "$IP_BIN" route replace "$subnet" via "$NAT_GATEWAY" dev eth0 src "$lan_ip" || return 1
    "$IP_BIN" route replace "$lan_ip/32" via "$nat_ip" dev "$BRIDGE" || return 1
    "$IP_BIN" neigh replace proxy "$lan_ip" dev "$UPLINK" || return 1
    # Android policy routing does not normally consult main for Wi-Fi peers.
    # The rule also lets reverse-path validation find those peers.
    ensure_lan_rule "$subnet" || return 1
)

db_lock() {
    count=0
    while ! mkdir "$DATA_DIR/.lock" 2>/dev/null; do
        count=$((count + 1))
        [ "$count" -lt 6 ] || return 1
        sleep 1
    done
}

db_unlock() {
    rmdir "$DATA_DIR/.lock" 2>/dev/null || true
}
