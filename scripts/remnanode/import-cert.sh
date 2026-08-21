#!/bin/bash

source "/opt/remnasetup/scripts/common/colors.sh"
source "/opt/remnasetup/scripts/common/functions.sh"
source "/opt/remnasetup/scripts/common/languages.sh"

# Switch an already-installed node's Caddy to a pre-issued wildcard cert
# (no ACME). Upload wildcard.crt + wildcard.key to /root/ (e.g. via WinSCP),
# then run this. Avoids Let's Encrypt rate limits across many nodes.
# Override paths with WILDCARD_CRT / WILDCARD_KEY; domain/port are taken from
# the existing Caddyfile or from BASE_DOMAIN / MONITOR_PORT / DOMAIN.

main() {
    info "$(get_string "import_cert_start")"

    if ! command -v caddy >/dev/null 2>&1; then
        error "$(get_string "import_cert_no_caddy")"
        pause_press_key "$(get_string "install_caddy_node_press_key")"
        exit 1
    fi

    local base="" port=""
    if [ -f /etc/caddy/Caddyfile ]; then
        local site
        site=$(grep -oE '\*\.[A-Za-z0-9.-]+:[0-9]+' /etc/caddy/Caddyfile | head -1)
        if [[ -n "$site" ]]; then
            base="${site#\*.}"; base="${base%:*}"
            port="${site##*:}"
        fi
    fi

    base="${BASE_DOMAIN:-$base}"
    port="${MONITOR_PORT:-${port:-8443}}"
    if [[ -z "$base" && -n "$DOMAIN" ]]; then
        base=$(derive_base_domain "$DOMAIN")
    fi
    if [[ -z "$base" ]]; then
        error "$(get_string "import_cert_no_domain")"
        pause_press_key "$(get_string "install_caddy_node_press_key")"
        exit 1
    fi

    info "BASE_DOMAIN=$base  MONITOR_PORT=$port"
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
