#!/usr/bin/env bash
# 在 Uppcoder 的 cpa 容器里装好 CLIProxyAPI 并挂到 supervisord。
# 用法: curl -fsSL https://raw.githubusercontent.com/rakaki/cliproxyapi-uppcoder/main/setup.sh | bash
set -euo pipefail

STATE="${CPAPI_STATE:-$HOME/cliproxyapi}"
VER="${CPAPI_VER:-8.0.69}"
PORT="${CPAPI_PORT:-8000}"
mkdir -p "$STATE/auth"

BIN="$STATE/cli-proxy-api"
if [ ! -x "$BIN" ]; then
  echo ">> 下载 CLIProxyAPI $VER"
  tmp=$(mktemp -d)
  curl -fsSL --retry 3 -o "$tmp/a.tgz" \
    "https://github.com/router-for-me/CLIProxyAPI/releases/download/v$VER/CLIProxyAPI_${VER}_linux_amd64.tar.gz"
  tar -xzf "$tmp/a.tgz" -C "$tmp"
  src=$(find "$tmp" -maxdepth 2 -type f -perm -u+x | head -n 1)
  install -m 755 "$src" "$BIN"
  rm -rf "$tmp"
fi

if [ ! -f "$STATE/config.yaml" ]; then
  KEY="sk-cpa-$(openssl rand -hex 16)"
  MKEY="$(openssl rand -hex 16)"
  cat > "$STATE/config.yaml" <<YAML
config-version: 8
server:
  host: ""
  port: $PORT
management:
  allow-remote: false
  secret-key: "$MKEY"
access:
  api-keys:
    - "$KEY"
oauth:
  auth-dir: "$STATE/auth"
YAML
  printf '%s\n' "$KEY" > "$STATE/api-key.txt"
  printf '%s\n' "$MKEY" > "$STATE/mgmt-key.txt"
  chmod 600 "$STATE/api-key.txt" "$STATE/mgmt-key.txt"
fi

CONF="$HOME/.config/supervisord.conf"
if ! grep -q '^\[program:framework\]' "$CONF"; then
  cat >> "$CONF" <<CONF2

; === CLIProxyAPI (managed by setup.sh) ===
[program:framework]
command=/bin/bash -lc 'cd $STATE && exec ./cli-proxy-api'
autostart=true
autorestart=true
startsecs=3
startretries=3
stdout_logfile=/home/uppcoder/log/framework-stdout.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=3
redirect_stderr=true
CONF2
fi

supervisorctl update >/dev/null 2>&1 || true
sleep 4
supervisorctl status framework || true
printf '>> local: '
curl -s -o /dev/null -w 'GET /v1/models -> %{http_code}\n' "http://127.0.0.1:$PORT/v1/models" || true
echo ">> API_KEY=$(cat "$STATE/api-key.txt" 2>/dev/null)"
echo ">> MGMT_KEY=$(cat "$STATE/mgmt-key.txt" 2>/dev/null)"
echo ">> log:"
tail -n 10 "$HOME/log/framework-stdout.log" 2>/dev/null || true
