#!/usr/bin/env bash
# Smart proxy for WSL: VPN/proxy optional; local + tunnel always direct.
# shellcheck disable=SC2034

DEVNET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
[ -f "${DEVNET_ROOT}/config.env" ] && source "${DEVNET_ROOT}/config.env"

DEVNET_PROXY_PORTS="${DEVNET_PROXY_PORTS:-7890 7897 10809 10808 20171}"
DEVNET_PROXY_SCHEME="${DEVNET_PROXY_SCHEME:-http}"
DEVNET_MODE="${DEVNET_MODE:-auto}"
DEVNET_GIT_MIRROR="${DEVNET_GIT_MIRROR:-https://ghproxy.net/}"

# Always bypass: local apps, WSL host, private LAN, Sealos / Sealtun.
# Keeps Windows→WSL port preview and sealtun stable whether proxy is on or off.
devnet_no_proxy_list() {
  local host
  host="$(devnet_windows_host 2>/dev/null || true)"
  local base="localhost,127.0.0.1,::1,.local,0.0.0.0"
  base+=",10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
  base+=",.sealos.run,.sealosgzg.site,.sealos.site,.aliyuncs.com"
  base+=",npm.taobao.org,registry.npmmirror.com,mirrors.aliyun.com"
  if [ -n "$host" ]; then
    base+=",${host}"
  fi
  printf '%s' "$base"
}

devnet_is_private_ip() {
  case "$1" in
    10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|127.*) return 0 ;;
    *) return 1 ;;
  esac
}

devnet_windows_host() {
  # Prefer default gateway (WSL NAT → Windows). Ignore public DNS like 8.8.8.8 in resolv.conf.
  local ip=""
  ip="$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')"
  if [ -n "$ip" ] && devnet_is_private_ip "$ip"; then
    echo "$ip"
    return 0
  fi
  if [ -f /etc/resolv.conf ]; then
    ip="$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)"
    if [ -n "$ip" ] && devnet_is_private_ip "$ip"; then
      echo "$ip"
      return 0
    fi
  fi
  # Mirrored / hostAddressLoopback fallback
  echo "127.0.0.1"
}

devnet_tcp_open() {
  local host="$1" port="$2"
  # Hard timeout — never hang doctor/git-clone on dead endpoints (e.g. public DNS:7890).
  if command -v timeout >/dev/null 2>&1; then
    timeout 0.4 bash -c "echo >/dev/tcp/${host}/${port}" >/dev/null 2>&1
    return $?
  fi
  (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1
}

# Echo "host:port" of first reachable Windows proxy, or empty.
devnet_detect_proxy_endpoint() {
  local host ports
  host="$(devnet_windows_host)"
  [ -z "$host" ] && return 1

  # Try Windows host first, then localhost (mirrored networking).
  local hosts=()
  if [ "$host" != "127.0.0.1" ]; then
    hosts+=("$host")
  fi
  hosts+=("127.0.0.1")
  # shellcheck disable=SC2206
  ports=(${DEVNET_PROXY_PORTS})

  local h p
  for h in "${hosts[@]}"; do
    for p in "${ports[@]}"; do
      if devnet_tcp_open "$h" "$p"; then
        echo "${h}:${p}"
        return 0
      fi
    done
  done
  return 1
}

devnet_clear_proxy_env() {
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
  unset ftp_proxy FTP_PROXY
  # Keep NO_PROXY so tools that always read it stay consistent.
  export NO_PROXY="$(devnet_no_proxy_list)"
  export no_proxy="$NO_PROXY"
}

devnet_apply_proxy_env() {
  local endpoint="$1"
  local url
  url="${DEVNET_PROXY_SCHEME}://${endpoint}"
  export http_proxy="$url"
  export https_proxy="$url"
  export HTTP_PROXY="$url"
  export HTTPS_PROXY="$url"
  export ALL_PROXY="$url"
  export all_proxy="$url"
  export NO_PROXY="$(devnet_no_proxy_list)"
  export no_proxy="$NO_PROXY"
}

# Preferred entry: respect DEVNET_MODE or first arg (auto|on|off).
devnet_proxy_apply() {
  local mode="${1:-${DEVNET_MODE:-auto}}"
  local endpoint=""

  case "$mode" in
    off | 0 | false)
      devnet_clear_proxy_env
      export DEVNET_PROXY_STATE="off"
      return 0
      ;;
    on | 1 | true)
      endpoint="$(devnet_detect_proxy_endpoint || true)"
      if [ -z "$endpoint" ]; then
        echo "[devnet] WARN: mode=on but no proxy port open on Windows host" >&2
        echo "[devnet] HINT: start Clash/V2Ray and enable Allow LAN" >&2
        devnet_clear_proxy_env
        export DEVNET_PROXY_STATE="off(missing)"
        return 1
      fi
      devnet_apply_proxy_env "$endpoint"
      export DEVNET_PROXY_STATE="on:${endpoint}"
      return 0
      ;;
    auto | *)
      endpoint="$(devnet_detect_proxy_endpoint || true)"
      if [ -n "$endpoint" ]; then
        devnet_apply_proxy_env "$endpoint"
        export DEVNET_PROXY_STATE="auto:on:${endpoint}"
      else
        devnet_clear_proxy_env
        export DEVNET_PROXY_STATE="auto:off"
      fi
      return 0
      ;;
  esac
}

devnet_git_use_mirror() {
  # Temporary insteadOf for this shell process only (not global config).
  local mirror="${DEVNET_GIT_MIRROR}"
  [ -z "$mirror" ] && return 0
  # Ensure trailing slash
  case "$mirror" in
    */) ;;
    *) mirror="${mirror}/" ;;
  esac
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="url.${mirror}https://github.com/.insteadOf"
  export GIT_CONFIG_VALUE_0="https://github.com/"
}

devnet_git_clear_mirror() {
  unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
}

# Call before git clone/fetch: proxy if available, else optional mirror.
devnet_git_prepare() {
  devnet_proxy_apply "${DEVNET_MODE:-auto}"
  case "${DEVNET_PROXY_STATE:-}" in
    on:* | auto:on:*)
      devnet_git_clear_mirror
      ;;
    *)
      if [ -n "${DEVNET_GIT_MIRROR:-}" ]; then
        devnet_git_use_mirror
      fi
      ;;
  esac
}

devnet_status() {
  local host
  host="$(devnet_windows_host || echo '?')"
  echo "=== devnet status ==="
  echo "windows_host : ${host}"
  echo "mode         : ${DEVNET_MODE:-auto}"
  echo "proxy_state  : ${DEVNET_PROXY_STATE:-"(not applied)"}"
  echo "http_proxy   : ${http_proxy:-(unset)}"
  echo "https_proxy  : ${https_proxy:-(unset)}"
  echo "NO_PROXY     : ${NO_PROXY:-(unset)}"
  echo "git_mirror   : ${DEVNET_GIT_MIRROR:-(none)}"
  if command -v git >/dev/null 2>&1; then
    echo "git version  : $(git --version 2>/dev/null)"
  fi
}

# Soft source helper for login shells / ProjectAccess scripts.
devnet_bootstrap() {
  # Always set NO_PROXY first so local curls never go through a stale proxy.
  export NO_PROXY="$(devnet_no_proxy_list)"
  export no_proxy="$NO_PROXY"
  devnet_proxy_apply "${DEVNET_MODE:-auto}" >/dev/null 2>&1 || true
}
