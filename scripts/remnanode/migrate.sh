#!/bin/bash

source "/opt/remnasetup/scripts/common/colors.sh"
source "/opt/remnasetup/scripts/common/functions.sh"
source "/opt/remnasetup/scripts/common/languages.sh"

SCRIPT_DIR="/opt/remnasetup"

# Migrate a node from the original (capybara) full install to the new scheme:
# random camouflage site + Caddy wildcard cert (self-steal) + WARP egress.
# Certs: if /root/wildcard.crt + /root/wildcard.key exist -> use them (no ACME),
# otherwise issue *.domain via Cloudflare DNS-01 (needs a token).

install_caddy_pkg() {
    if command -v nginx >/dev/null 2>&1; then
        systemctl stop nginx 2>/dev/null || true
        systemctl disable nginx 2>/dev/null || true
    fi
    wait_for_apt
    apt-get update -y
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl libcap2-bin
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -y
    apt-get install -y caddy
}

main() {
    info "$(get_string "migrate_start")"
    echo ""

    # --- Domain / port --------------------------------------------------------
    if [[ -z "${DOMAIN:-}" ]]; then
        if is_non_interactive; then
            error "DOMAIN environment variable is required in non-interactive mode."
            exit 1
        fi
        while true; do
            question "$(get_string "migrate_enter_domain")"
            DOMAIN="$REPLY"
            [[ -n "$DOMAIN" ]] && break
            warn "$(get_string "install_caddy_node_domain_empty")"
        done
    else
        info "DOMAIN=$DOMAIN"
    fi
    local base
    base=$(derive_base_domain "$DOMAIN")
    MONITOR_PORT="${MONITOR_PORT:-8443}"
    info "BASE_DOMAIN=$base  MONITOR_PORT=$MONITOR_PORT"
    echo ""

    # --- Caddy present? -------------------------------------------------------
    if ! command -v caddy >/dev/null 2>&1; then
        info "$(get_string "install_caddy_node_installing")"
        install_caddy_pkg
    fi

    # --- Camouflage site (replace the old 503 decoy) --------------------------
    info "$(get_string "migrate_site")"
    deploy_random_site "/var/www/site"
    echo ""

    # --- Wildcard cert: ready-made (/root) or issue via Cloudflare ------------
    if [[ -f /root/wildcard.crt && -f /root/wildcard.key ]] || [[ -n "${WILDCARD_CRT:-}" && -n "${WILDCARD_KEY:-}" ]]; then
        info "$(get_string "migrate_cert_ready")"
        apply_caddy_manual_cert "$base" "$MONITOR_PORT" || exit 1
    else
        info "$(get_string "migrate_cert_issue")"
        if [[ -z "${CF_API_TOKEN:-}" ]]; then
            if is_non_interactive; then
                error "CF_API_TOKEN is required (no certs in /root)."
                exit 1
            fi
            while true; do
                question "$(get_string "install_caddy_node_enter_cf_token")"
                CF_API_TOKEN="$REPLY"
                [[ -n "$CF_API_TOKEN" ]] && break
                warn "$(get_string "install_caddy_node_token_empty")"
            done
        fi
        if [[ -z "${ACME_EMAIL:-}" ]] && ! is_non_interactive; then
            question "$(get_string "install_caddy_node_enter_acme_email")"
            ACME_EMAIL="$REPLY"
        fi

        ensure_caddy_cloudflare || { error "$(get_string "install_caddy_node_plugin_failed")"; exit 1; }
        set_caddy_cf_token "$CF_API_TOKEN" || exit 1

        cp "$SCRIPT_DIR/data/caddy/caddyfile-node" /etc/caddy/Caddyfile
        sed -i "s/\$BASE_DOMAIN/$base/g" /etc/caddy/Caddyfile
        sed -i "s/\$MONITOR_PORT/$MONITOR_PORT/g" /etc/caddy/Caddyfile
        if [[ -n "${ACME_EMAIL:-}" ]]; then
            sed -i "s/\$ACME_EMAIL/$ACME_EMAIL/g" /etc/caddy/Caddyfile
        else
            sed -i "/email \$ACME_EMAIL/d" /etc/caddy/Caddyfile
        fi
        systemctl enable caddy >/dev/null 2>&1 || true
        systemctl restart caddy
        success "$(get_string "install_caddy_node_config_updated")"
    fi
    echo ""

    # --- WARP egress ----------------------------------------------------------
    if [[ -f /etc/wireguard/warp.conf ]] && wg show warp >/dev/null 2>&1; then
        info "$(get_string "migrate_warp_exists")"
        ensure_warp_routing
    else
        info "$(get_string "migrate_warp_install")"
        bash "$SCRIPT_DIR/scripts/remnanode/install-warp.sh"
    fi
    echo ""

    # --- Done + panel reminder ------------------------------------------------
    success "$(get_string "migrate_done")"
    echo ""
    echo -e "${BOLD_CYAN}$(get_string "migrate_panel_title")${RESET}"
    echo -e "${BLUE}  • Reality: target = 127.0.0.1:$MONITOR_PORT, serverNames = $DOMAIN${RESET}"
    echo -e "${BLUE}  • DNS: queryStrategy = UseIPv4${RESET}"
    echo -e "${BLUE}  • outbound warp {freedom, sockopt.mark:1} + routing rule (network tcp,udp -> warp)${RESET}"
    echo -e "${BLUE}  • $(get_string "migrate_panel_subs")${RESET}"
    echo ""
    echo | openssl s_client -connect 127.0.0.1:"$MONITOR_PORT" -servername "$DOMAIN" 2>/dev/null \
        | openssl x509 -noout -subject -issuer 2>/dev/null | sed 's/^/    /'

    pause_press_key "$(get_string "install_caddy_node_press_key")"
    exit 0
}

main
