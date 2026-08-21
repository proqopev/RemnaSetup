#!/bin/bash

source "/opt/remnasetup/scripts/common/colors.sh"
source "/opt/remnasetup/scripts/common/functions.sh"
source "/opt/remnasetup/scripts/common/languages.sh"

# Switch a node's Caddy to a pre-issued wildcard cert (no ACME). Builds a fresh
# Caddyfile (*.domain + manual tls), replacing any old one — no manual editing.
# Upload wildcard.crt + wildcard.key to /root/ (WinSCP), then run this.
# Override paths with WILDCARD_CRT / WILDCARD_KEY; domain/port via DOMAIN /
# BASE_DOMAIN / MONITOR_PORT or the interactive prompt.

main() {
    info "$(get_string "import_cert_start")"

    if ! command -v caddy >/dev/null 2>&1; then
        error "$(get_string "import_cert_no_caddy")"
        pause_press_key "$(get_string "install_caddy_node_press_key")"
        exit 1
    fi

    # Best-effort default: base domain / port from an existing wildcard Caddyfile.
    local base_from_conf="" port_from_conf=""
    if [ -f /etc/caddy/Caddyfile ]; then
        local site
        site=$(grep -oE '\*\.[A-Za-z0-9.-]+:[0-9]+' /etc/caddy/Caddyfile | head -1)
        if [[ -n "$site" ]]; then
            base_from_conf="${site#\*.}"; base_from_conf="${base_from_conf%:*}"
            port_from_conf="${site##*:}"
        fi
    fi

    # Resolve base domain: env wins, else prompt (default = value from Caddyfile).
    local base=""
    if [[ -n "${BASE_DOMAIN:-}" ]]; then
        base="$BASE_DOMAIN"
    elif [[ -n "${DOMAIN:-}" ]]; then
        base=$(derive_base_domain "$DOMAIN")
    else
        base="$base_from_conf"
    fi

    if ! is_non_interactive; then
        local prompt="$(get_string "import_cert_enter_domain")"
        [[ -n "$base" ]] && prompt="$prompt [$base]"
        while true; do
            question "$prompt: "
            if [[ -n "$REPLY" ]]; then
                base=$(derive_base_domain "$REPLY"); break
            elif [[ -n "$base" ]]; then
                break
            fi
            warn "$(get_string "install_caddy_node_domain_empty")"
        done
    fi

    if [[ -z "$base" ]]; then
        error "$(get_string "import_cert_no_domain")"
        pause_press_key "$(get_string "install_caddy_node_press_key")"
        exit 1
    fi

    local port="${MONITOR_PORT:-${port_from_conf:-8443}}"

    info "$(get_string "import_cert_building") *.$base:$port"
    if ! apply_caddy_manual_cert "$base" "$port"; then
        pause_press_key "$(get_string "install_caddy_node_press_key")"
        exit 1
    fi

    echo ""
    info "$(get_string "import_cert_verify")"
    echo | openssl s_client -connect 127.0.0.1:"$port" -servername "node.$base" 2>/dev/null \
        | openssl x509 -noout -subject -issuer -dates 2>/dev/null | sed 's/^/    /'

    pause_press_key "$(get_string "install_caddy_node_press_key")"
    exit 0
}

main
