#!/bin/bash
# Distribute a pre-issued wildcard cert to many nodes over SSH and switch each
# node's Caddy to it (no ACME). Run from YOUR machine (Git Bash on Windows works).
#
# Nodes are addressed by their ~/.ssh/config aliases (login by name, key auth).
# Use it for the initial rollout AND for renewals (re-issue on the master,
# then run this again to push the new cert everywhere).
#
# Usage:
#   ./deploy-cert.sh -d datahubfiles.com node1 node2 node3
#   ./deploy-cert.sh -d datahubfiles.com -f hosts.txt
#   ./deploy-cert.sh -d datahubfiles.com --from-ssh-config
#
# Options:
#   -d DOMAIN            base domain (e.g. datahubfiles.com)     [required]
#   -c FILE             cert file   (default ./wildcard.crt)
#   -k FILE             key file    (default ./wildcard.key)
#   -p PORT             MONITOR_PORT (default 8443)
#   -u USER             ssh user (default: taken from ~/.ssh/config)
#   -f FILE             read hosts from file (one per line, # comments ok)
#   --from-ssh-config   use every Host alias from ~/.ssh/config
#   -y                  skip the confirmation prompt

set -u
CRT="wildcard.crt"; KEY="wildcard.key"; DOMAIN=""; PORT="8443"; SSH_USER=""; YES=0
REPO="${REMNASETUP_REPO:-proqopev/RemnaSetup}"
hosts=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) DOMAIN="$2"; shift 2 ;;
    -c) CRT="$2"; shift 2 ;;
    -k) KEY="$2"; shift 2 ;;
    -p) PORT="$2"; shift 2 ;;
    -u) SSH_USER="$2"; shift 2 ;;
    -y) YES=1; shift ;;
    -f) mapfile -t _f < <(grep -vE '^[[:space:]]*(#|$)' "$2"); hosts+=("${_f[@]}"); shift 2 ;;
    --from-ssh-config)
        mapfile -t _c < <(grep -iE '^[[:space:]]*Host[[:space:]]+' "$HOME/.ssh/config" 2>/dev/null \
          | awk '{for(i=2;i<=NF;i++) print $i}' | grep -vE '[*?]')
        hosts+=("${_c[@]}"); shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) hosts+=("$1"); shift ;;
  esac
done

[[ -z "$DOMAIN" ]] && { echo "ERROR: -d DOMAIN is required"; exit 1; }
[[ -f "$CRT" && -f "$KEY" ]] || { echo "ERROR: cert files not found ($CRT / $KEY)"; exit 1; }
[[ ${#hosts[@]} -gt 0 ]] || { echo "ERROR: no hosts given (pass names, -f file, or --from-ssh-config)"; exit 1; }

echo "Domain : $DOMAIN   (port $PORT)"
echo "Cert   : $CRT / $KEY"
echo "Repo   : $REPO"
echo "Hosts  : ${hosts[*]}"
if [[ "$YES" -ne 1 ]]; then
  read -r -p "Deploy to ${#hosts[@]} host(s)? [y/N] " ans
  [[ "$ans" == y* || "$ans" == Y* ]] || { echo "aborted"; exit 0; }
fi

ok=0; fail=0; failed=()
for h in "${hosts[@]}"; do
  target="$h"; [[ -n "$SSH_USER" ]] && target="$SSH_USER@$h"
  echo ""; echo "=== $h ==="
  if scp -q "$CRT" "$target:/root/wildcard.crt" \
     && scp -q "$KEY" "$target:/root/wildcard.key" \
     && ssh "$target" "curl -fsSL https://raw.githubusercontent.com/$REPO/refs/heads/main/install.sh | BASE_DOMAIN='$DOMAIN' MONITOR_PORT='$PORT' bash -s -- import-cert"; then
    echo "  OK"; ok=$((ok+1))
  else
    echo "  FAILED"; fail=$((fail+1)); failed+=("$h")
  fi
done

echo ""; echo "Done: $ok ok, $fail failed."
[[ $fail -gt 0 ]] && echo "Failed hosts: ${failed[*]}"
exit 0
