#!/usr/bin/env bash
# 在 Uppcoder 容器里一键装好并启动 CLIProxyAPI。
# 用法（在 stack 的 VS Code 终端里）:
#   curl -fsSL https://raw.githubusercontent.com/rakaki/cliproxyapi-uppcoder/main/bootstrap.sh | bash
# 可选环境变量: CPAPI_STATE(状态目录) PORT(监听端口)
set -euo pipefail

VER="${CPAPI_VER:-8.0.69}"
STATE="${CPAPI_STATE:-}"
if [ -z "$STATE" ]; then
  for c in /data/cliproxyapi "$HOME/cliproxyapi"; do
    if mkdir -p "$c" 2>/dev/null && [ -w "$c" ]; then STATE="$c"; break; fi
  done
fi
[ -n "$STATE" ] || { echo "no writable state dir" >&2; exit 1; }
mkdir -p "$STATE/auth"
cd "$STATE"

BIN="$STATE/cli-proxy-api"
if [ ! -x "$BIN" ]; then
  echo "installing CLIProxyAPI $VER into $STATE"
  url="https://github.com/router-for-me/CLIProxyAPI/releases/download/v$VER/CLIProxyAPI_${VER}_linux_amd64.tar.gz"
  tmp=$(mktemp -d)
  curl -fsSL --retry 3 -o "$tmp/a.tgz" "$url"
  tar -xzf "$tmp/a.tgz" -C "$tmp"
  src=$(find "$tmp" -maxdepth 2 -type f -perm -u+x | head -n 1)
  [ -n "$src" ] || { echo "no binary in archive" >&2; exit 1; }
  install -m 755 "$src" "$BIN"
  rm -rf "$tmp"
fi

if [ ! -f "$STATE/config.yaml" ]; then
  cat > "$STATE/config.yaml" <<'YAML'
config-version: 8
server:
  host: ""
  port: 8317
management:
  allow-remote: true
  secret-key: ""
access:
  api-keys:
    - "change-me"
oauth:
  auth-dir: "~/.cli-proxy-api"
YAML
fi

sed -i "s/^  port:.*/  port: ${PORT:-8317}/" "$STATE/config.yaml"
sed -i "s|^  auth-dir:.*|  auth-dir: \"$STATE/auth\"|" "$STATE/config.yaml"

exec "$BIN"
