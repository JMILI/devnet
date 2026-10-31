#!/usr/bin/env bash
# Smoke: network layer + onlineProject/rust-compile-web local preview.
# Does NOT require VPN. Tunnel optional via ProjectAccess (deploy copy).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/proxy.sh
source "${ROOT}/lib/proxy.sh"
CODE_JM="$(cd "${ROOT}/.." && pwd)"
ONLINE_RCW="${CODE_JM}/onlineProject/rust-compile-web"
PA="${CODE_JM}/deployProject/ProjectAccess"

devnet_proxy_apply auto
echo "[smoke] DEVNET_PROXY_STATE=${DEVNET_PROXY_STATE}"

echo "[smoke] doctor (subset)..."
"${ROOT}/bin/net" doctor || true

if [ ! -d "$ONLINE_RCW" ]; then
  echo "[smoke] onlineProject/rust-compile-web missing — skip local start"
  exit 0
fi

# Prefer ProjectAccess-managed rust-compile (ports + sealtun already wired).
# onlineProject tree is for编辑/对照；运行与隧道走 deployProject。
echo
echo "[smoke] start deployProject rust-compile (local only)..."
cd "$PA"
SKIP_TUNNEL=1 bash start_all.sh rust-compile

echo
bash status_all.sh || true

echo
echo "[smoke] Windows / WSL local URLs (VPN-independent):"
echo "  UI : http://127.0.0.1:5175/"
echo "  API: http://127.0.0.1:18080/   (or :8080)"
echo
echo "[smoke] optional tunnel:"
echo "  sealtun login gzg"
echo "  bash tunnel.sh apply rust-compile"
echo "  # or: bash start_all.sh rust-compile   # without SKIP_TUNNEL"
echo
echo "[smoke] optional git clone into onlineProject:"
echo "  cd ${CODE_JM}/onlineProject && ${ROOT}/bin/net git-clone https://github.com/JMILI/ProjectAccess.git"
