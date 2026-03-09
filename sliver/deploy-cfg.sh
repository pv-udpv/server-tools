#!/usr/bin/env bash
# Deploy e2b-bravo cfg to sliver-client and disable local@127.0.0.1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_DIR="${HOME}/.sliver-client/configs"

mkdir -p "${CFG_DIR}"
mkdir -p "${CFG_DIR}/_disabled"

# 1. Disable any 127.0.0.1 configs
for f in "${CFG_DIR}"/*127.0.0.1*; do
  [[ -f "$f" ]] && mv "$f" "${CFG_DIR}/_disabled/" && echo "[~] disabled: $(basename $f)"
done

# 2. Deploy external C2 cfg
cp "${SCRIPT_DIR}/configs/e2b-bravo_46.161.5.162.cfg" "${CFG_DIR}/"
chmod 600 "${CFG_DIR}/e2b-bravo_46.161.5.162.cfg"
echo "[+] deployed: e2b-bravo_46.161.5.162.cfg"

# 3. Verify
echo "[*] configs in ${CFG_DIR}:"
ls -la "${CFG_DIR}/"*.cfg 2>/dev/null || echo "  (none)"
echo ""
echo "[*] disabled:"
ls "${CFG_DIR}/_disabled/" 2>/dev/null || echo "  (none)"

echo ""
echo "Now run:"
echo "  ./sliver-client -config ${CFG_DIR}/e2b-bravo_46.161.5.162.cfg"
echo "  sliver > beacons"
echo "  sliver > use ENCHANTING_STEPPING-STONE"
