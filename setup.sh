#!/usr/bin/env bash
# 在 Uppcoder 的 cpa 容器里装好 CLIProxyAPI 并尽量挂到 supervisord（无权限时退回 nohup+crontab）。
# 用法: curl -fsSL https://raw.githubusercontent.com/rakaki/cliproxyapi-uppcoder/main/setup.sh | bash
set -uo pipefail

STATE="${CPAPI_STATE:-$HOME/cliproxyapi}"
VER="${CPAPI_VER:-8.0.69}"
PORT="${CPAPI_PORT:-8000}"
LOG="$HOME/log/framework-stdout.log"
mkdir -p "$STATE/auth" "$HOME/log"

BIN="$STATE/cli-proxy-api"
if [ ! -x "$BIN" ]; then
  echo ">> 下载 CLIProxyAPI $VER"
  tmp=$(mktemp -d)
  curl -fsSL --retry 3 -o "$tmp/a.tgz" \
    "https://github.com/router-for-me/CLIProxyAPI/releases/download/v$VER/CLIProxyAPI_${VER}_linux_amd64.tar.gz" || { echo "!! 下载失败"; exit 1; }
  tar -xzf "$tmp/a.tgz" -C "$tmp" || { echo "!! 解包失败"; exit 1; }
  src=$(find "$tmp" -maxdepth 2 -type f -perm -u+x | head -n 1)
  install -m 755 "$src" "$BIN" || { echo "!! 安装失败"; exit 1; }
  rm -rf "$tmp"
fi
echo ">> 二进制: $(ls -lh "$BIN" | awk '{print $5}')"

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

SUPCTL=""
for c in "$(command -v supervisorctl 2>/dev/null || true)" /opt/pixi/.pixi/envs/default/bin/supervisorctl; do
  if [ -n "$c" ] && [ -x "$c" ]; then SUPCTL="$c"; break; fi
done
echo ">> supervisorctl: ${SUPCTL:-未找到}"

CONF="$HOME/.config/supervisord.conf"
if [ -n "$SUPCTL" ] && [ -w "$CONF" ] && ! grep -q '^\[program:framework\]' "$CONF"; then
  cat >> "$CONF" <<CONF2

; === CLIProxyAPI (managed by setup.sh) ===
[program:framework]
command=/bin/bash -lc 'cd $STATE && exec ./cli-proxy-api'
autostart=true
autorestart=true
startsecs=3
startretries=3
stdout_logfile=$LOG
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=3
redirect_stderr=true
CONF2
  echo ">> 已写入 [program:framework]"
fi

RUNNING=0
if [ -n "$SUPCTL" ]; then
  if $SUPCTL update >/tmp/sup.out 2>&1; then
    sleep 4
    $SUPCTL status framework || true
    RUNNING=1
  else
    echo "!! supervisorctl 失败: $(head -3 /tmp/sup.out | tr '\n' ' ')"
  fi
fi

if [ "$RUNNING" = "0" ]; then
  echo ">> 退回 nohup 启动"
  cd "$STATE" && nohup ./cli-proxy-api >>"$LOG" 2>&1 &
  echo $! > "$STATE/pid"
  sleep 4
  if command -v crontab >/dev/null 2>&1; then
    ( crontab -l 2>/dev/null | grep -v 'cli-proxy-api'; \
      echo "@reboot cd $STATE && ./cli-proxy-api >> $LOG 2>&1" ) | crontab - 2>/dev/null \
      && echo ">> 已写入 crontab @reboot" || echo ">> crontab 写不进去，重启后需手动拉起"
  fi
fi

printf '>> local: '
curl -s -o /dev/null -w 'GET /v1/models -> %{http_code}\n' "http://127.0.0.1:$PORT/v1/models" || true
echo ">> API_KEY=$(cat "$STATE/api-key.txt" 2>/dev/null)"
echo ">> MGMT_KEY=$(cat "$STATE/mgmt-key.txt" 2>/dev/null)"
echo ">> log:"
tail -n 12 "$LOG" 2>/dev/null || echo "  (无日志)"
