#!/usr/bin/env bash
# e2b_sliver_tailscale_setup.sh — Full E2B sandbox setup
# Swap → Go → Sliver (source) → Tailscale + MagicDNS + Subnet Router
# Usage: TS_AUTHKEY=tskey-auth-XXX bash e2b_sliver_tailscale_setup.sh
set -euo pipefail

SANDBOX_ID="${E2B_SANDBOX_ID:-$(hostname)}"
SWAP_SIZE="${SWAP_SIZE:-2G}"
GO_VERSION="${GO_VERSION:-1.22.5}"
SLIVER_BRANCH="${SLIVER_BRANCH:-master}"
TS_SUBNET="${TS_SUBNET:-10.47.0.0/24}"
WORK="/home/user/workspace"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
info()  { echo -e "${G}[+]${N} $*"; }
warn()  { echo -e "${Y}[~]${N} $*"; }
err()   { echo -e "${R}[!]${N} $*"; }

[[ -z "${TS_AUTHKEY:-}" ]] && { err "TS_AUTHKEY required"; exit 1; }

echo "=== E2B Sliver+Tailscale | sandbox=${SANDBOX_ID} swap=${SWAP_SIZE} ==="

# 1) SWAP
info "Step 1: Swap ${SWAP_SIZE}"
if ! swapon --show | grep -q swapfile; then
  sudo fallocate -l ${SWAP_SIZE} /swapfile && sudo chmod 600 /swapfile
  sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile
fi
free -h | grep -E 'Mem|Swap'

# 2) GO
info "Step 2: Go ${GO_VERSION}"
if ! go version 2>/dev/null | grep -q "${GO_VERSION}"; then
  cd /tmp
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o go.tgz
  sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go.tgz
fi
export PATH="/usr/local/go/bin:${HOME}/go/bin:${PATH}"
go version

# 3) SLIVER BUILD
info "Step 3: Sliver from source (${SLIVER_BRANCH})"
mkdir -p "${WORK}"
if [[ ! -f "${WORK}/sliver/sliver-server" ]]; then
  sudo apt-get update -qq && sudo apt-get install -y -qq git make gcc >/dev/null 2>&1
  [[ ! -d "${WORK}/sliver/.git" ]] && \
    git clone --depth=1 -b "${SLIVER_BRANCH}" https://github.com/BishopFox/sliver.git "${WORK}/sliver"
  cd "${WORK}/sliver"
  ./go-assets.sh
  make linux-amd64
fi
sudo ln -sf "${WORK}/sliver/sliver-server" /usr/local/bin/
sudo ln -sf "${WORK}/sliver/sliver-client" /usr/local/bin/
sliver-server version 2>/dev/null || true

# 4) TAILSCALE
info "Step 4: Tailscale install"
command -v tailscale &>/dev/null || curl -fsSL https://tailscale.com/install.sh | sudo bash

# 5) TAILSCALE UP + SUBNET
info "Step 5: tailscale up --hostname=${SANDBOX_ID} --advertise-routes=${TS_SUBNET}"
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-ts.conf >/dev/null
echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.d/99-ts.conf >/dev/null
sudo sysctl -p /etc/sysctl.d/99-ts.conf >/dev/null 2>&1

pgrep -x tailscaled &>/dev/null || { sudo tailscaled --state=/var/lib/tailscale/tailscaled.state & sleep 2; }

sudo tailscale up \
  --authkey="${TS_AUTHKEY}" \
  --hostname="${SANDBOX_ID}" \
  --advertise-routes="${TS_SUBNET}" \
  --accept-dns=true \
  --accept-routes=true \
  --reset

TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
TS_FQDN="${SANDBOX_ID}.$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("MagicDNSSuffix","ts.net"))' 2>/dev/null || echo 'ts.net')"

# 6) SLIVER DAEMON
info "Step 6: Sliver server start"
sliver-server unpack --force 2>/dev/null || true
sliver-server daemon &
SRV_PID=$!; sleep 3
mkdir -p ~/.sliver-client/configs
sliver-server operator --name "${SANDBOX_ID}" --lhost 127.0.0.1 \
  --save ~/.sliver-client/configs/${SANDBOX_ID}.cfg 2>/dev/null || true

info "=== DONE ==="
cat <<EOF

  Tailscale:  ${TS_FQDN} (${TS_IP})
  Subnet:     ${TS_SUBNET} (approve in admin console!)
  MagicDNS:   ${SANDBOX_ID}.tail*.ts.net
  Sliver PID: ${SRV_PID}

  Quick:
    sliver-client
    sliver > mtls --lhost ${TS_FQDN}
    sliver > generate --mtls ${TS_FQDN} --os linux
    sliver > ssh user@${TS_FQDN}  # via Tailscale SSH
EOF
