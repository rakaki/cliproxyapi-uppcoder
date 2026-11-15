package main

// Uppcoder 上跑 CLIProxyAPI 的启动器。
// 平台用 go build 构建本文件，产物就是入口；真正的进程是持久盘上的官方二进制。
// 首次启动会自己下载发行包，之后每次都复用磁盘上的副本，升级只改 ver 一行。

import (
	"os"
	"os/exec"
)

const ver = "8.0.69"

const defaultConfig = `config-version: 8
server:
  host: ""
  port: 8317
management:
  allow-remote: false
  secret-key: ""
access:
  api-keys:
    - "change-me"
oauth:
  auth-dir: "~/.cli-proxy-api"
`

const script = `
set -eu
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

[ -f "$STATE/config.yaml" ] || printf '%s' "$DEFAULT_CONFIG" > "$STATE/config.yaml"

sed -i "s/^  port:.*/  port: ${PORT:-8317}/" "$STATE/config.yaml"
sed -i "s|^  auth-dir:.*|  auth-dir: "$STATE/auth"|" "$STATE/config.yaml"

exec "$BIN"
`

func main() {
	cmd := exec.Command("bash", "-c", script)
	cmd.Env = append(os.Environ(),
		"DEFAULT_CONFIG="+defaultConfig,
		"VER="+ver,
	)
	cmd.Stdout, cmd.Stderr, cmd.Stdin = os.Stdout, os.Stderr, os.Stdin
	if err := cmd.Run(); err != nil {
		os.Exit(1)
	}
}
