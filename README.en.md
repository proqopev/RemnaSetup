# RemnaSetup

<div align="center">

[English](README.en.md) | [Русский](README.md)

![RemnaSetup](https://img.shields.io/badge/RemnaSetup-2.5-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-orange)

Script for installing and managing **Remnawave** and **Remnanode** infrastructure

[![Stars](https://img.shields.io/github/stars/proqopev/RemnaSetup?style=social)](https://github.com/proqopev/RemnaSetup)

</div>

---

## Installation

```bash
bash <(curl -fsSL raw.githubusercontent.com/proqopev/RemnaSetup/refs/heads/main/install.sh)
```

or

```bash
curl -fsSL https://raw.githubusercontent.com/proqopev/RemnaSetup/refs/heads/main/install.sh -o install.sh && chmod +x install.sh && sudo bash ./install.sh
```

### Installing from your own fork

If you use your own copy of the repository, point to it with `REMNASETUP_REPO` —
`install.sh` will download exactly that one:

```bash
REMNASETUP_REPO=youruser/RemnaSetup \
bash <(curl -fsSL https://raw.githubusercontent.com/youruser/RemnaSetup/refs/heads/main/install.sh)
```

### One-command node install

Fully non-interactive, with Caddy + Cloudflare wildcard:

```bash
NON_INTERACTIVE=true \
DOMAIN=node1.example.com \
CF_API_TOKEN='cloudflare_api_token' \
ACME_EMAIL='you@example.com' \
NODE_PORT=3001 SECRET_KEY='key_from_panel' \
WEBSERVER=caddy INSTALL_WARP=y BBR_ANSWER=y \
PANEL_IP=1.2.3.4 \
bash <(curl -fsSL https://raw.githubusercontent.com/proqopev/RemnaSetup/refs/heads/main/install.sh) install-node
```

`PANEL_IP` enables ufw rules that open the management ports `3001,61000` only to
the panel IP; public ports `22,80,443` are open to everyone; `8443` (self-steal
Caddy) is **not** exposed — Reality reaches it via `127.0.0.1`. `fail2ban`
(`sshd` jail) is installed too. Disable with `SKIP_FIREWALL=true` / `SKIP_FAIL2BAN=true`.

---

## Features

### Remnawave (panel)
- Full install (Remnawave + Caddy)
- Panel / subscription page / Caddy separately
- Updates for all components
- Backup and restore (manual, automatic, to Telegram or S3 storage)

### Remnanode (node)
- Full install (Remnanode + Caddy/Nginx + BBR + WARP)
- Node image version selection (`latest` or `X.Y.Z`) — important for panel/node compatibility
- Web server of choice: **Caddy** or **Nginx** with self-steal
- **Caddy**: wildcard certificate `*.domain` via Cloudflare DNS-01 (the `caddy-dns/cloudflare` plugin is built in automatically) — only the wildcard shows up in CT logs, individual node names stay hidden
- Nginx: proxy protocol support, certificates via Cloudflare DNS-01 / HTTP-01 / Gcore DNS-01
- **Random camouflage site** from a set of natural templates (café, consulting, photo, SaaS, bookshop, studio, portfolio) — different on each node, with a unique micro-markup; a real 404 on random paths
- **ufw firewall**: public `22,80,443`, management ports `3001,61000` only for the panel IP, `8443` closed to the outside
- **fail2ban** (`sshd` jail)
- **WARP egress for xray**: installing WARP on a node sets up fwmark policy routing (traffic marked `mark=1` exits through Cloudflare, so the node IP is not exposed as an exit). For existing nodes — the `setup-warp-routing` command. In the panel you add an outbound `{tag: warp, protocol: freedom, sockopt.mark: 1}` + a routing rule and `dns.queryStrategy: UseIPv4`
- IPv6 management
- WARP-NATIVE (by distillium)
- BBR optimization

---

## Preparation: domain on Cloudflare (wildcard certificate)

For Caddy to obtain a single **wildcard** certificate `*.example.com` instead of a
separate one per node name (otherwise every node name appears in public CT logs and
can be found with one `crt.sh` query), the domain must be on Cloudflare and issuance
must go through ACME **DNS-01**.

1. **Add the domain to Cloudflare** → Dashboard → *Add a Site* → your domain → **Free** plan.
   Cloudflare imports current DNS records — verify the node A-records are there.
2. **Change NS at the registrar** — Cloudflare gives two nameservers; set them at your
   registrar instead of the current ones. Propagation takes 10 minutes to a few hours.
   Check: `dig NS example.com` shows the Cloudflare NS.
3. ⚠️ **Node A-records must be `DNS only` (grey cloud).** The orange cloud (Proxied) breaks
   Reality: the client must see your server's real IP in the TLS handshake, not Cloudflare's.
4. **Create an API token** → profile icon → *My Profile* → *API Tokens* → *Create Custom Token*:
   - **Permissions:** `Zone → DNS → Edit`
   - **Zone Resources:** `Include → Specific zone → example.com`
   - Copy the token (shown once) — this is `CF_API_TOKEN` for the script.

Then, when installing Caddy, the script builds Caddy with the `caddy-dns/cloudflare`
plugin, stores the token in a systemd override, and issues `*.example.com` via DNS-01.
The node name is a random string (e.g. `x7f2qk9z.example.com`), but only `*.example.com`
appears in CT logs.

---

## Configuring the Reality profile in Remnawave

The script sets up the server side (Caddy/self-steal, certificate, host-side WARP), but
the **xray config in the panel is edited by hand**. The minimum you need:

### 1. Reality inbound (self-steal)
- `target` (a.k.a. `dest`) → **`127.0.0.1:8443`** — Reality forwards uninvited visitors to
  the local Caddy (port = your `MONITOR_PORT`). A bare `"8443"` with no host is unreliable.
- `serverNames` → the full node name (e.g. `x7f2qk9z.example.com`), **not** the wildcard.
- `xver` → `0` for Caddy (for Nginx with proxy protocol — `1`).

### 2. WARP egress (so the node IP is not exposed as an exit)
Host-side routing is set up by the script (`install-warp` or `setup-warp-routing`). In the
panel, add three things to the xray config:

**DNS — IPv4 only** (WARP is configured IPv4-only):
```json
"dns": { "servers": ["https://1.1.1.1/dns-query"], "queryStrategy": "UseIPv4" }
```

**Outbound `warp`** (the `mark=1` matches the host fwmark rule):
```json
{
  "tag": "warp",
  "protocol": "freedom",
  "settings": { "domainStrategy": "ForceIPv4" },
  "streamSettings": { "sockopt": { "mark": 1 } }
}
```

**Routing** — block rules first, the warp "catch-all" last (all traffic via Cloudflare):
```json
"rules": [
  { "type": "field", "ip": ["geoip:private"], "outboundTag": "BLOCK" },
  { "type": "field", "domain": ["geosite:private"], "outboundTag": "BLOCK" },
  { "type": "field", "protocol": ["bittorrent"], "outboundTag": "BLOCK" },
  { "type": "field", "network": "tcp,udp", "outboundTag": "warp" }
]
```

Verify from a client: `https://www.cloudflare.com/cdn-cgi/trace` → `warp=on` and a Cloudflare
IP (not the node IP).

> ⚠️ Do not apply a profile with `outboundTag: warp` to a node that has no host-side WARP
> routing (`setup-warp-routing`) — the marked traffic would have nowhere to go and that
> node's users would go offline.

---

## Non-interactive mode

You can pass parameters via environment variables and a command — the script runs without prompts.

### Full node install with Caddy (Cloudflare DNS-01 wildcard)

```bash
DOMAIN=node1.example.com \
MONITOR_PORT=8443 \
NODE_PORT=3001 \
SECRET_KEY='your_key' \
WEBSERVER=caddy \
CF_API_TOKEN='cloudflare_api_token' \
ACME_EMAIL='you@example.com' \
INSTALL_WARP=y \
BBR_ANSWER=y \
sudo -E bash /opt/remnasetup/remnasetup.sh install-node
```

> `DOMAIN` is the full node name (`node1.example.com`); the wildcard certificate is issued
> for the base zone (`*.example.com`), derived automatically. `CF_API_TOKEN` is a Cloudflare
> token with **Zone → DNS → Edit** on your zone. `ACME_EMAIL` is optional. The token is stored
> in a Caddy systemd override, not in the Caddyfile. Optionally
> `SITE_TEMPLATE=cafe|consulting|photography|saas|bookshop|studio|devportfolio` forces a
> specific camouflage template (random by default).

### Full node install with Nginx

```bash
DOMAIN=node1.example.com \
MONITOR_PORT=8443 \
NODE_PORT=3001 \
SECRET_KEY='your_key' \
WEBSERVER=nginx \
USE_PROXY_PROTOCOL=n \
CERT_METHOD=1 \
CF_API_KEY='token' \
CF_EMAIL='email@example.com' \
INSTALL_WARP=y \
BBR_ANSWER=y \
sudo -E bash /opt/remnasetup/remnasetup.sh install-node
```

### Skipping components

```bash
DOMAIN=node1.example.com \
WEBSERVER=caddy \
MONITOR_PORT=8443 \
SKIP_REMNANODE=true \
SKIP_WARP=true \
SKIP_BBR=true \
sudo -E bash /opt/remnasetup/remnasetup.sh install-node
```

### Available commands

| Command | Description |
|---|---|
| `install-node` | Full node install |
| `install-node-only` | Remnanode only |
| `install-caddy-node` | Caddy only |
| `install-nginx-node` | Nginx only |
| `install-bbr` | BBR only |
| `install-warp` | WARP only |
| `setup-warp-routing` | Route xray egress through an already-installed WARP (for existing nodes) |
| `import-cert` | Switch Caddy to a pre-issued wildcard cert (no ACME) — for scaling to many nodes |
| `update-node` | Update Remnanode |

### Environment variables

| Variable | Description | Default |
|---|---|---|
| `DOMAIN` | Node domain | — |
| `MONITOR_PORT` | Web server port | `8443` |
| `NODE_PORT` | Node port | `3001` |
| `NODE_VERSION` | Node image version — `latest` or `X.Y.Z` (e.g. `3.2.2`) | `latest` |
| `SECRET_KEY` | Panel connection key | — |
| `WEBSERVER` | `caddy` or `nginx` | — |
| `CF_API_TOKEN` | Cloudflare API token for Caddy (Zone:DNS:Edit) | — |
| `ACME_EMAIL` | Email for ACME in Caddy (optional) | — |
| `WILDCARD_CRT` | Path to a pre-issued wildcard cert → Caddy without ACME | `/root/wildcard.crt` |
| `WILDCARD_KEY` | Path to the key of the pre-issued cert → Caddy without ACME | `/root/wildcard.key` |
| `SITE_TEMPLATE` | Force a camouflage template (otherwise random) | random |
| `BASE_DOMAIN` | Explicit zone for the wildcard (otherwise from `DOMAIN`) | auto |
| `USE_PROXY_PROTOCOL` | `y` / `n` (for nginx) | — |
| `CERT_METHOD` | `1` (Cloudflare) / `2` (HTTP-01) / `3` (Gcore) | — |
| `CF_API_KEY` | Cloudflare API token (cert_method=1) | — |
| `CF_EMAIL` | Cloudflare email (cert_method=1) | — |
| `LE_EMAIL` | Email for the certificate (cert_method=2/3) | — |
| `GCORE_API_KEY` | Gcore API token (cert_method=3) | — |
| `INSTALL_WARP` | `y` / `n` | — |
| `BBR_ANSWER` | `y` / `n` | — |
| `PANEL_IP` | Panel IP — restrict management ports (3001,61000) to it only | — |
| `FIREWALL_TCP_PORTS` | Public TCP ports for ufw | `22,80,443` |
| `NODE_MGMT_PORTS` | Management ports opened only to `PANEL_IP` | `3001,61000` |
| `SKIP_FIREWALL` | `true` — do not configure ufw | — |
| `SKIP_FAIL2BAN` | `true` — do not install fail2ban | — |
| `SKIP_WEBSERVER` | `true` — skip the web server | — |
| `SKIP_REMNANODE` | `true` — skip the node | — |
| `SKIP_WARP` | `true` — skip WARP | — |
| `SKIP_BBR` | `true` — skip BBR | — |
| `UPDATE_REMNANODE` | `true` — reinstall the node | — |
| `UPDATE_CADDY` | `true` — reinstall Caddy | — |
| `UPDATE_NGINX` | `true` — reinstall Nginx | — |
| `LANGUAGE` | `ru` / `en` | `ru` |

Without arguments the script runs in the usual interactive menu mode.

---

## Automatic backups

Schedule: daily at a set time or every N hours (configured via cron).

Three storage options are available:

1. **Telegram** — send the archive to a Telegram chat via a bot
2. **S3 storage** — upload to any S3-compatible storage
3. **Local** — on the server only

### S3 storage

Any S3-compatible storage is supported (Yandex Object Storage, Selectel, Timeweb, MinIO, etc.).

You will be asked for:

| Parameter | Description | Default |
|---|---|---|
| Endpoint | S3 service URL | — |
| Access Key | Access key | — |
| Secret Key | Secret key | — |
| Bucket | Bucket name | — |
| Region | Region | — |
| Path | Path (prefix) inside the bucket | — |
| Keep | Number of backups to keep in S3 (`0` — keep all) | — |

On a manual backup, if S3 was configured before, the script offers to upload the archive to the same storage.

---

## Contacts

GitHub: [@proqopev](https://github.com/proqopev)

## Credits

A fork of [Capybara-z/RemnaSetup](https://github.com/Capybara-z/RemnaSetup).
WARP-NATIVE — by distillium. Made with support from [SoloBot](https://github.com/Vladless/Solo_bot).

## License

MIT
