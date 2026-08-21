#!/bin/bash

source "/opt/remnasetup/scripts/common/colors.sh"
source "/opt/remnasetup/scripts/common/languages.sh"

info() {
    echo -e "${BOLD_CYAN}[INFO]${RESET} $1"
}

warn() {
    echo -e "${BOLD_YELLOW}[WARN]${RESET} $1"
}

error() {
    echo -e "${BOLD_RED}[ERROR]${RESET} $1"
}

success() {
    echo -e "${BOLD_GREEN}[SUCCESS]${RESET} $1"
}

menu() {
    echo -e "${BOLD_MAGENTA}$1${RESET}"
    read -p "$(echo -e "${BOLD_CYAN}$(get_string "select_menu_option"):${RESET}") " choice
    echo "$choice"
}

question() {
    read -p "$(echo -e "${BOLD_CYAN}$1${RESET}") " REPLY
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        error "$(get_string "root_required")"
        exit 1
    fi
}

check_directory() {
    if [ ! -d "$1" ]; then
        error "$(get_string "directory_not_exist" "$1")"
        exit 1
    fi
}

check_file() {
    if [ ! -f "$1" ]; then
        error "$(get_string "file_not_exist" "$1")"
        exit 1
    fi
}

create_directory() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
    fi
}

backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$1.bak"
    fi
}

restore_file() {
    if [ -f "$1.bak" ]; then
        mv "$1.bak" "$1"
    fi
}

detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v apk &> /dev/null; then
        echo "apk"
    else
        echo "unknown"
    fi
}

update_package_list() {
    local pm=$(detect_package_manager)
    case "$pm" in
        apt)
            apt-get update -y
            ;;
        yum)
            yum check-update -y || true
            ;;
        dnf)
            dnf check-update -y || true
            ;;
        apk)
            apk update
            ;;
        *)
            error "Unsupported package manager"
            return 1
            ;;
    esac
}

install_packages() {
    local pm=$(detect_package_manager)
    local packages="$@"
    
    case "$pm" in
        apt)
            apt-get install -y $packages
            ;;
        yum)
            yum install -y $packages
            ;;
        dnf)
            dnf install -y $packages
            ;;
        apk)
            apk add --no-cache $packages
            ;;
        *)
            error "Unsupported package manager"
            return 1
            ;;
    esac
}

ensure_package() {
    local package="$1"
    if command_exists "$package"; then
        return 0
    fi

    local install_name="$package"
    case "$package" in
        7z)
            local pm=$(detect_package_manager)
            if [ "$pm" = "apt" ]; then
                install_name="p7zip-full"
            else
                install_name="p7zip"
            fi
            ;;
    esac
    
    info "Installing $install_name..."
    update_package_list
    install_packages "$install_name"
}

# Wait until apt/dpkg locks are released (e.g. unattended-upgrades running in the
# background). Degrades gracefully if `fuser` is absent. Times out after 5 min.
wait_for_apt() {
    local waited=0
    while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; do
        warn "$(get_string "apt_locked_waiting")"
        sleep 3
        waited=$((waited + 3))
        if [ "$waited" -ge 300 ]; then
            warn "apt still locked after 5 min — continuing anyway."
            break
        fi
    done
    # Recover from an interrupted dpkg (E: dpkg was interrupted...).
    dpkg --configure -a >/dev/null 2>&1 || true
}

is_non_interactive() {
    if [[ "$NON_INTERACTIVE" == "true" || "$NON_INTERACTIVE" == "1" ]]; then
        return 0
    fi
    if [[ "$CI" == "true" || "$CI" == "1" ]]; then
        return 0
    fi
    if [ ! -t 0 ]; then
        return 0
    fi
    return 1
}

pause_press_key() {
    local prompt="$1"
    if is_non_interactive; then
        return 0
    fi
    read -n 1 -s -r -p "$prompt"
    echo
}

# --- Camouflage site helpers -------------------------------------------------

# Derive the registrable base domain (zone) from a full FQDN.
# e.g. x7f2qk9z.datahubfiles.com -> datahubfiles.com
# Note: naive two-label split, same limitation as the nginx path
# (does not special-case multi-part TLDs like .co.uk). Override with BASE_DOMAIN.
derive_base_domain() {
    local fqdn="$1"
    if [[ -n "$BASE_DOMAIN" ]]; then
        echo "$BASE_DOMAIN"
        return 0
    fi
    echo "$fqdn" | awk -F. '{ if (NF>=2) print $(NF-1)"."$NF; else print $0 }'
}

# Deploy a random self-contained decoy site from data/sites into the target dir.
# Each node gets a light, unique tweak (meta id + comment + body class) so two
# nodes that happen to pick the same theme are not byte-identical.
# Env override: SITE_TEMPLATE=<theme> forces a specific template.
# Exports: SELECTED_SITE_TEMPLATE
deploy_random_site() {
    local target="${1:-/var/www/site}"
    local sites_dir="/opt/remnasetup/data/sites"

    if [ ! -d "$sites_dir" ]; then
        error "Camouflage templates not found: $sites_dir"
        return 1
    fi

    local themes=()
    local d
    for d in "$sites_dir"/*/; do
        [ -d "$d" ] && themes+=("$(basename "$d")")
    done
    if [ ${#themes[@]} -eq 0 ]; then
        error "No camouflage templates available in $sites_dir"
        return 1
    fi

    local pick="${themes[$RANDOM % ${#themes[@]}]}"
    if [[ -n "$SITE_TEMPLATE" && -d "$sites_dir/$SITE_TEMPLATE" ]]; then
        pick="$SITE_TEMPLATE"
    fi

    mkdir -p "$target"
    rm -rf "${target:?}/"* 2>/dev/null || true
    cp -r "$sites_dir/$pick/." "$target/"

    local rid rcomment rclass rmeta
    rid=$(openssl rand -hex 16)
    rcomment=$(openssl rand -hex 12)
    rclass=$(openssl rand -hex 8)
    local metas=("render-id" "view-id" "page-id" "config-id" "build-id")
    rmeta=${metas[$RANDOM % ${#metas[@]}]}

    if [ -f "$target/index.html" ]; then
        sed -i "/<meta name=\"viewport\"/a \    <meta name=\"$rmeta\" content=\"$rid\">\n    <!-- $rcomment -->" "$target/index.html" 2>/dev/null || true
        sed -i "0,/<body\([ >]\)/s//<body class=\"$rclass\"\1/" "$target/index.html" 2>/dev/null || true
    fi

    chmod -R a+rX "$target"
    SELECTED_SITE_TEMPLATE="$pick"
    export SELECTED_SITE_TEMPLATE
    info "Camouflage template: $pick"
    return 0
}

# Ensure the installed caddy binary includes the Cloudflare DNS provider module
# (needed for ACME DNS-01 / wildcard certificates). If not present, fetch a
# custom build from the official caddyserver.com download API and replace the
# binary. Falls back to xcaddy (requires Go) if the download API is unreachable.
ensure_caddy_cloudflare() {
    if command -v caddy >/dev/null 2>&1 && caddy list-modules 2>/dev/null | grep -q 'dns.providers.cloudflare'; then
        info "Caddy already has the Cloudflare DNS plugin."
        return 0
    fi

    local caddy_bin
    caddy_bin=$(command -v caddy 2>/dev/null)
    caddy_bin="${caddy_bin:-/usr/bin/caddy}"

    local arch
    case "$(uname -m)" in
        x86_64|amd64)   arch="amd64" ;;
        aarch64|arm64)  arch="arm64" ;;
        armv7l)         arch="arm&arm=7" ;;
        *)              arch="amd64" ;;
    esac

    info "Building Caddy with the Cloudflare DNS plugin..."
    local tmp
    tmp=$(mktemp -d)
    local url="https://caddyserver.com/api/download?os=linux&arch=${arch}&p=github.com/caddy-dns/cloudflare"

    if curl -fsSL "$url" -o "$tmp/caddy" && [ -s "$tmp/caddy" ]; then
        chmod +x "$tmp/caddy"
        if "$tmp/caddy" list-modules 2>/dev/null | grep -q 'dns.providers.cloudflare'; then
            systemctl stop caddy 2>/dev/null || true
            cp "$tmp/caddy" "$caddy_bin"
            if command -v setcap >/dev/null 2>&1; then
                setcap 'cap_net_bind_service=+ep' "$caddy_bin" 2>/dev/null || true
            fi
            rm -rf "$tmp"
            success "Caddy with Cloudflare plugin installed at $caddy_bin"
            return 0
        fi
    fi

    warn "Download API build failed, trying xcaddy (this installs Go and may take a while)..."
    rm -rf "$tmp"

    if ! command -v go >/dev/null 2>&1; then
        apt-get install -y golang-go || return 1
    fi
    if ! command -v xcaddy >/dev/null 2>&1; then
        go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest || return 1
        export PATH="$PATH:$(go env GOPATH)/bin"
    fi

    local build_dir
    build_dir=$(mktemp -d)
    ( cd "$build_dir" && xcaddy build --with github.com/caddy-dns/cloudflare ) || { rm -rf "$build_dir"; return 1; }

    if [ -x "$build_dir/caddy" ] && "$build_dir/caddy" list-modules 2>/dev/null | grep -q 'dns.providers.cloudflare'; then
        systemctl stop caddy 2>/dev/null || true
        cp "$build_dir/caddy" "$caddy_bin"
        command -v setcap >/dev/null 2>&1 && setcap 'cap_net_bind_service=+ep' "$caddy_bin" 2>/dev/null || true
        rm -rf "$build_dir"
        success "Caddy with Cloudflare plugin built via xcaddy and installed at $caddy_bin"
        return 0
    fi

    rm -rf "$build_dir"
    error "Failed to build Caddy with the Cloudflare DNS plugin."
    return 1
}

# Ask for / validate the Remnawave node image tag. Accepts "latest" or X.Y.Z
# (e.g. 3.2.2). Sets NODE_VERSION (default "latest").
# NOTE: panel/node versions must be compatible — e.g. panel 2.7.4 does not work
# with node 3.3.2 (changed panel<->node handshake); pin an older tag if needed.
request_node_version() {
    if [[ -n "$NODE_VERSION" ]]; then
        if [[ "$NODE_VERSION" =~ ^(latest|[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
            info "NODE_VERSION=$NODE_VERSION"
            return 0
        else
            error "$(get_string "install_node_version_invalid")"
            exit 1
        fi
    fi

    if is_non_interactive; then
        NODE_VERSION="latest"
        info "Non-interactive mode: NODE_VERSION defaulted to $NODE_VERSION"
        return 0
    fi

    while true; do
        question "$(get_string "install_node_enter_version")"
        NODE_VERSION="$REPLY"
        NODE_VERSION="${NODE_VERSION:-latest}"
        if [[ "$NODE_VERSION" =~ ^(latest|[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
            break
        fi
        warn "$(get_string "install_node_version_invalid")"
    done
}

# Store the Cloudflare API token as a systemd environment variable for caddy,
# so {env.CF_API_TOKEN} in the Caddyfile resolves at runtime (token is never
# written into the Caddyfile itself).
set_caddy_cf_token() {
    local token="$1"
    if [[ -z "$token" ]]; then
        error "set_caddy_cf_token: empty token"
        return 1
    fi
    mkdir -p /etc/systemd/system/caddy.service.d
    cat > /etc/systemd/system/caddy.service.d/10-cf-token.conf <<EOF
[Service]
Environment="CF_API_TOKEN=$token"
EOF
    chmod 600 /etc/systemd/system/caddy.service.d/10-cf-token.conf
    systemctl daemon-reload
    return 0
}

# Configure Caddy to serve a PRE-ISSUED wildcard cert instead of doing ACME.
# This is how you scale to many nodes without hitting Let's Encrypt rate limits:
# issue *.domain once on a "cert master", then distribute the crt+key and call
# this on every node (no ACME, no Cloudflare token, no plugin needed here).
# Inputs (env, with defaults): WILDCARD_CRT=/root/wildcard.crt WILDCARD_KEY=/root/wildcard.key
# Args: $1 = base domain (e.g. datahubfiles.com), $2 = port (e.g. 8443)
apply_caddy_manual_cert() {
    local base="$1" port="$2"
    local crt="${WILDCARD_CRT:-/root/wildcard.crt}"
    local key="${WILDCARD_KEY:-/root/wildcard.key}"

    if [[ ! -f "$crt" || ! -f "$key" ]]; then
        error "$(get_string "caddy_cert_files_missing") ($crt / $key)"
        return 1
    fi
    if [[ -z "$base" || -z "$port" ]]; then
        error "apply_caddy_manual_cert: base domain / port not set"
        return 1
    fi

    mkdir -p /etc/caddy/certs
    install -m 644 "$crt" /etc/caddy/certs/wildcard.crt
    install -m 600 "$key" /etc/caddy/certs/wildcard.key
    id caddy >/dev/null 2>&1 && chown -R caddy:caddy /etc/caddy/certs

    cp "/opt/remnasetup/data/caddy/caddyfile-node-cert" /etc/caddy/Caddyfile
    sed -i "s|\$BASE_DOMAIN|$base|g" /etc/caddy/Caddyfile
    sed -i "s|\$MONITOR_PORT|$port|g" /etc/caddy/Caddyfile
    sed -i "s|\$CERT_CRT|/etc/caddy/certs/wildcard.crt|g" /etc/caddy/Caddyfile
    sed -i "s|\$CERT_KEY|/etc/caddy/certs/wildcard.key|g" /etc/caddy/Caddyfile

    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy
    success "$(get_string "caddy_cert_applied")"
    return 0
}

# Set up fwmark policy routing so that traffic marked by xray (sockopt mark=1)
# egresses through the WARP interface, while the node's own traffic stays on the
# main interface. Idempotent — safe to run on new or already-installed nodes.
# The matching xray outbound in the panel must set:
#   "streamSettings": { "sockopt": { "mark": 1 } }
WARP_ROUTING_TABLE_DEFAULT="51820"
ensure_warp_routing() {
    local conf="/etc/wireguard/warp.conf"
    local table="${WARP_ROUTING_TABLE:-$WARP_ROUTING_TABLE_DEFAULT}"

    if [ ! -f "$conf" ]; then
        error "$(get_string "warp_routing_no_conf")"
        return 1
    fi

    # Persist across reboots: add PostUp/PostDown into the [Interface] section
    # (must be above [Peer], otherwise wg-quick passes them to `wg` and fails).
    if grep -q "table ${table}" "$conf"; then
        info "$(get_string "warp_routing_already")"
    else
        sed -i "/^\[Interface\]/a PostUp = ip rule add fwmark 0x1 table ${table} || true\nPostUp = ip route add default dev warp table ${table} || true\nPostDown = ip rule del fwmark 0x1 table ${table} || true" "$conf"
        info "$(get_string "warp_routing_added")"
    fi

    # Apply immediately for the running interface.
    ip rule add fwmark 0x1 table "${table}" 2>/dev/null || true
    if ip link show warp >/dev/null 2>&1; then
        ip route replace default dev warp table "${table}"
    fi

    # Keep exactly one fwmark rule (drop duplicates from earlier manual runs).
    while [ "$(ip rule show 2>/dev/null | grep -c "fwmark 0x1 lookup ${table}")" -gt 1 ]; do
        ip rule del fwmark 0x1 table "${table}" 2>/dev/null || break
    done

    success "$(get_string "warp_routing_done")"
    return 0
}

export -f info
export -f warn
export -f error
export -f success
export -f menu
export -f question
export -f command_exists
export -f check_root
export -f check_directory
export -f check_file
export -f create_directory
export -f backup_file
export -f restore_file
export -f detect_package_manager
export -f update_package_list
export -f install_packages
export -f ensure_package
export -f is_non_interactive
export -f wait_for_apt
export -f pause_press_key
export -f derive_base_domain
export -f deploy_random_site
export -f ensure_caddy_cloudflare
export -f set_caddy_cf_token
export -f request_node_version
export -f ensure_warp_routing
export -f apply_caddy_manual_cert
