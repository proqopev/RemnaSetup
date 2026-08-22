#!/bin/bash

source "/opt/remnasetup/scripts/common/colors.sh"
source "/opt/remnasetup/scripts/common/functions.sh"
source "/opt/remnasetup/scripts/common/languages.sh"

# Disable WARP egress on a node (e.g. dual-IP nodes that egress via a second IP).
# Stops the tunnel, removes the fwmark policy routing and the watchdog. After
# this, xray's marked traffic falls back to the default route (the node's normal
# egress IP), so clients keep working — no panel change strictly required.
# Reversible: re-enable with the WARP install + setup-warp-routing.

main() {
    info "$(get_string "disable_warp_start")"
    local table="${WARP_ROUTING_TABLE:-51820}"

    # Stop the tunnel and its autostart.
    systemctl disable --now wg-quick@warp >/dev/null 2>&1 || true

    # Remove the fwmark policy routing (live).
    local n=0
    while ip rule show 2>/dev/null | grep -q "fwmark 0x1 lookup ${table}"; do
        ip rule del fwmark 0x1 table "${table}" 2>/dev/null || break
        n=$((n + 1)); [ "$n" -ge 20 ] && break
    done
    ip route flush table "${table}" 2>/dev/null || true

    # Stop the watchdog from bringing WARP back.
    rm -f /etc/cron.d/warp-native

    # Strip the routing PostUp/PostDown from warp.conf (keep the rest for reuse).
    if [ -f /etc/wireguard/warp.conf ]; then
        sed -i "/table ${table}/d" /etc/wireguard/warp.conf 2>/dev/null || true
    fi

    success "$(get_string "disable_warp_done")"
    echo ""
    info "$(get_string "disable_warp_panel_hint")"
    pause_press_key "$(get_string "install_caddy_node_press_key")"
    exit 0
}

main
