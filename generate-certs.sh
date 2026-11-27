#!/usr/bin/env bash
# 生成自签名 TLS 证书（供 Nginx HTTPS 使用）
# 用法：
#   ./generate-certs.sh [SERVER_NAME]
# 不指定时优先读取 .env 中的 SERVER_NAME，默认 localhost
set -euo pipefail

cd "$(dirname "$0")"

# 解析域名：参数 > .env > 默认 localhost
SERVER_NAME="${1:-}"
if [[ -z "$SERVER_NAME" && -f .env ]]; then
  line="$(grep -E '^SERVER_NAME=' .env | head -n1 || true)"
  SERVER_NAME="${line#*=}"
  SERVER_NAME="${SERVER_NAME//[[:space:]]/}"
  SERVER_NAME="${SERVER_NAME//\"/}"
  SERVER_NAME="${SERVER_NAME//\'/}"
fi
SERVER_NAME="${SERVER_NAME:-localhost}"

CERT_DIR="./certs"
KEY="$CERT_DIR/nginx.key"
CRT="$CERT_DIR/nginx.crt"
DAYS="${CERT_DAYS:-3650}"

mkdir -p "$CERT_DIR"

# 构造 SAN：访问名（IP 用 IP: 前缀）+ localhost + 127.0.0.1，避免重复
if [[ "$SERVER_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  SAN="IP:${SERVER_NAME}"
else
  SAN="DNS:${SERVER_NAME}"
fi
[[ "${SERVER_NAME}" != "localhost" ]] && SAN="${SAN},DNS:localhost"
SAN="${SAN},IP:127.0.0.1"

echo "生成自签名证书 -> 域名: $SERVER_NAME, 有效期: $DAYS 天"
echo "SAN: $SAN"

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$KEY" \
  -out "$CRT" \
  -days "$DAYS" \
  -subj "/CN=${SERVER_NAME}" \
  -addext "subjectAltName=${SAN}" \
  -addext "keyUsage=digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth"

chmod 600 "$KEY"
chmod 644 "$CRT"

echo "完成："
echo "  $CRT"
echo "  $KEY"
