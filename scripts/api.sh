#!/system/bin/sh
MODDIR=${0%/*}/..
. "$MODDIR/scripts/lib.sh"

init_data || { echo 'Cannot initialize module data' >&2; exit 1; }
action=${1:-}

case "$action" in
    list)
        current_cidr=$(phone_cidr)
        if daemon_ready; then daemon=ready; else daemon=waiting; fi
        printf 'META|%s|%s\n' "$current_cidr" "$daemon"
        for cfg in "$CONTAINERS_DIR"/*/container.config; do
            [ -f "$cfg" ] || continue
            [ "$(cfg_value net_mode "$cfg")" = nat ] || continue
            name=$(cfg_value name "$cfg")
            valid_name "$name" || continue
            saved=$(assignment "$name")
            lan_ip=$(printf '%s\n' "$saved" | cut -d '|' -f 1)
            bound_cidr=$(printf '%s\n' "$saved" | cut -d '|' -f 2)
            [ -n "$saved" ] || { lan_ip=; bound_cidr=; }
            pid=$(container_pid "$name")
            if [ -n "$pid" ]; then nat_ip=$(container_nat_ip "$pid"); else nat_ip=; fi
            if [ -z "$lan_ip" ]; then
                state=unassigned
            elif [ -z "$pid" ]; then
                state=stopped
            elif [ "$current_cidr" != "$bound_cidr" ]; then
                state=other_lan
            elif mapping_active "$name" "$lan_ip" "$bound_cidr"; then
                state=active
            else
                state=pending
            fi
            printf 'CONTAINER|%s|%s|%s|%s|%s\n' "$name" "$nat_ip" "$lan_ip" "$bound_cidr" "$state"
            if [ -n "$pid" ] && [ -n "$nat_ip" ]; then
                "$NSENTER_BIN" -t "$pid" -n -- "$IP_BIN" -4 -o addr show dev eth0 2>/dev/null |
                    awk '$3 == "inet" && $4 ~ /\/32$/ { sub(/\/32$/, "", $4); print $4 }' |
                    while IFS= read -r extra_ip; do
                        [ "$extra_ip" != "$lan_ip" ] || continue
                        ip_to_u32 "$extra_ip" >/dev/null || continue
                        "$IP_BIN" -4 route show "$extra_ip/32" 2>/dev/null |
                            grep -Fq "via $nat_ip dev $BRIDGE" || continue
                        proxy_present "$extra_ip" || continue
                        printf 'EXTRA|%s|%s\n' "$name" "$extra_ip"
                    done
            fi
        done
        while IFS='|' read -r name lan_ip bound_cidr; do
            valid_name "$name" || continue
            ip_to_u32 "$lan_ip" >/dev/null || continue
            nat_config "$name" >/dev/null && continue
            printf 'SAVED|%s|%s|%s\n' "$name" "$lan_ip" "$bound_cidr"
        done <"$DB"
        ;;
    set)
        name=${2:-}
        lan_ip=${3:-}
        valid_name "$name" || { echo 'Invalid container name' >&2; exit 2; }
        nat_config "$name" >/dev/null || { echo 'Container is not in NAT mode' >&2; exit 2; }
        current_cidr=$(phone_cidr)
        [ -n "$current_cidr" ] || { echo 'Connect the phone to Wi-Fi first' >&2; exit 2; }
        ip_on_phone_lan "$lan_ip" "$current_cidr" || { echo 'IP must be a usable address on the phone Wi-Fi subnet' >&2; exit 2; }
        db_lock || { echo 'Configuration is busy' >&2; exit 1; }
        trap 'db_unlock' EXIT INT TERM
        owner=$(assignment_owner "$lan_ip")
        if [ -n "$owner" ] && [ "$owner" != "$name" ]; then
            echo 'IP is already assigned to another container' >&2
            exit 2
        fi
        old=$(assignment "$name")
        old_ip=$(printf '%s\n' "$old" | cut -d '|' -f 1)
        old_cidr=$(printf '%s\n' "$old" | cut -d '|' -f 2)
        tmp=$DATA_DIR/assignments.$$
        awk -F '|' -v wanted="$name" '$1 != wanted { print }' "$DB" >"$tmp" || exit 1
        printf '%s|%s|%s\n' "$name" "$lan_ip" "$current_cidr" >>"$tmp"
        mv "$tmp" "$DB" || exit 1
        db_unlock
        trap - EXIT INT TERM
        if [ -n "$old" ] && [ "$old_ip" != "$lan_ip" ]; then remove_mapping "$name" "$old_ip"; fi
        if [ -n "$old" ]; then remove_lan_rule_if_unused "$old_cidr"; fi
        if daemon_ready; then apply_mapping "$name" "$lan_ip" "$current_cidr" || exit 1; fi
        printf 'Saved %s as %s\n' "$name" "$lan_ip"
        ;;
    delete)
        name=${2:-}
        valid_name "$name" || { echo 'Invalid container name' >&2; exit 2; }
        db_lock || { echo 'Configuration is busy' >&2; exit 1; }
        trap 'db_unlock' EXIT INT TERM
        old=$(assignment "$name")
        [ -n "$old" ] || { echo 'No saved IP for this container' >&2; exit 2; }
        old_ip=$(printf '%s\n' "$old" | cut -d '|' -f 1)
        old_cidr=$(printf '%s\n' "$old" | cut -d '|' -f 2)
        tmp=$DATA_DIR/assignments.$$
        awk -F '|' -v wanted="$name" '$1 != wanted { print }' "$DB" >"$tmp" || exit 1
        mv "$tmp" "$DB" || exit 1
        db_unlock
        trap - EXIT INT TERM
        remove_mapping "$name" "$old_ip"
        remove_lan_rule_if_unused "$old_cidr"
        printf 'Removed %s from %s\n' "$old_ip" "$name"
        ;;
    delete-extra)
        name=${2:-}
        extra_ip=${3:-}
        valid_name "$name" && ip_to_u32 "$extra_ip" >/dev/null || { echo 'Invalid container or IP' >&2; exit 2; }
        nat_config "$name" >/dev/null || { echo 'Container is not in NAT mode' >&2; exit 2; }
        saved=$(assignment "$name")
        saved_ip=$(printf '%s\n' "$saved" | cut -d '|' -f 1)
        [ "$extra_ip" != "$saved_ip" ] || { echo 'Use Remove IP for the saved assignment' >&2; exit 2; }
        pid=$(container_pid "$name") || { echo 'Container is stopped' >&2; exit 2; }
        nat_ip=$(container_nat_ip "$pid")
        [ -n "$nat_ip" ] || { echo 'Container has no NAT address' >&2; exit 2; }
        "$NSENTER_BIN" -t "$pid" -n -- "$IP_BIN" -4 -o addr show dev eth0 2>/dev/null |
            grep -Fq "inet $extra_ip/32 " || { echo 'IP is not assigned to this container' >&2; exit 2; }
        "$IP_BIN" -4 route show "$extra_ip/32" 2>/dev/null |
            grep -Fq "via $nat_ip dev $BRIDGE" || { echo 'Host route does not point to this container' >&2; exit 2; }
        proxy_present "$extra_ip" || { echo 'No proxy ARP entry for this IP' >&2; exit 2; }
        remove_mapping "$name" "$extra_ip"
        if [ -n "$saved" ] && daemon_ready; then
            saved_cidr=$(printf '%s\n' "$saved" | cut -d '|' -f 2)
            apply_mapping "$name" "$saved_ip" "$saved_cidr" || exit 1
        fi
        printf 'Removed extra %s from %s\n' "$extra_ip" "$name"
        ;;
    sync)
        while IFS='|' read -r name lan_ip bound_cidr; do
            valid_name "$name" || continue
            ip_to_u32 "$lan_ip" >/dev/null || continue
            if daemon_ready; then
                apply_mapping "$name" "$lan_ip" "$bound_cidr" || exit 1
            else
                remove_mapping "$name" "$lan_ip"
            fi
        done <"$DB"
        ;;
    cleanup)
        while IFS='|' read -r name lan_ip bound_cidr; do
            valid_name "$name" || continue
            ip_to_u32 "$lan_ip" >/dev/null || continue
            remove_mapping "$name" "$lan_ip"
            remove_lan_rule "$bound_cidr"
        done <"$DB"
        ;;
    *)
        echo 'Usage: api.sh list | set CONTAINER IPv4 | delete CONTAINER | delete-extra CONTAINER IPv4 | sync | cleanup' >&2
        exit 2
        ;;
esac
