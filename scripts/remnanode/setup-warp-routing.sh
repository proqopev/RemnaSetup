#!/bin/bash

source "/opt/remnasetup/scripts/common/colors.sh"
source "/opt/remnasetup/scripts/common/functions.sh"
source "/opt/remnasetup/scripts/common/languages.sh"

# Apply WARP fwmark egress routing to a node that already has WARP-NATIVE
# installed (adds PostUp/PostDown to warp.conf + applies live). Non-disruptive:
# does not restart the tunnel, so users stay online.

main() {
    info "$(get_string "warp_routing_start")"

    if ! command -v wg >/dev/null 2>&1 || [ ! -f /etc/wireguard/warp.conf ]; then
        error "$(get_string "warp_routing_not_installed")"
        pause_press_key "$(get_string "warp_native_press_key")"
        exit 1
    fi

    if ! ensure_warp_routing; then
        pause_press_key "$(get_string "warp_native_press_key")"
        exit 1
    fi

    local table="${WARP_ROUTING_TABLE:-51820}"
    echo ""
    info "$(get_string "warp_routing_verify")"
    echo -e "    ip route get 1.1.1.1 mark 1   ->  dev warp"
    ip route get 1.1.1.1 mark 1 2>/dev/null | sed 's/^/    /'
    echo ""
    warn "$(get_string "warp_routing_panel_hint")"

    pause_press_key "$(get_string "warp_native_press_key")"
    exit 0
}

main
