#!/bin/bash

# MQTT Gear Server - TLS 憑證生成腳本

set -e

# 載入配置
if [ -f ".env" ]; then
    source .env
fi

MQTT_BROKER_IP=${MQTT_BROKER_IP:-140.134.60.218}

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo "🔒 MQTT TLS 憑證生成工具"
echo "=========================="
echo ""

# 檢查 OpenSSL
if ! command -v openssl &> /dev/null; then
    print_error "OpenSSL 未安裝，請先安裝 OpenSSL"
    exit 1
fi

# 創建 certs 目錄
mkdir -p certs
cd certs

# 檢查現有憑證
if [ -f "server.crt" ] && [ -f "ca.crt" ]; then
    print_warning "發現現有憑證文件"
    echo ""
    echo "現有憑證信息："
    openssl x509 -in server.crt -text -noout | grep -E "(Subject:|DNS:|IP Address:)" || true
    echo ""
    
    read -p "是否要重新生成憑證？這將覆蓋現有文件 (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_info "保留現有憑證"
        exit 0
    fi
    
    # 備份現有憑證
    timestamp=$(date +%Y%m%d_%H%M%S)
    print_info "備份現有憑證..."
    [ -f "server.crt" ] && mv server.crt "server.crt.backup_$timestamp"
    [ -f "ca.crt" ] && mv ca.crt "ca.crt.backup_$timestamp"
    [ -f "server.key" ] && mv server.key "server.key.backup_$timestamp"
    [ -f "ca.key" ] && mv ca.key "ca.key.backup_$timestamp"
fi

print_info "生成 TLS 自簽名憑證 (IP: $MQTT_BROKER_IP)..."

# 生成 CA 私鑰
print_info "生成 CA 私鑰..."
openssl genrsa -out ca.key 4096

# 生成 CA 根憑證
print_info "生成 CA 根憑證..."
openssl req -new -x509 -key ca.key -out ca.crt -days 3650 \
    -subj "/C=TW/ST=Taiwan/L=Taipei/O=MQTT-Gear-Server/OU=Certificate Authority/CN=MQTT-CA"

# 生成服務器私鑰
print_info "生成服務器私鑰..."
openssl genrsa -out server.key 4096

# 生成服務器憑證請求
print_info "生成服務器憑證請求..."
openssl req -new -key server.key -out server.csr \
    -subj "/C=TW/ST=Taiwan/L=Taipei/O=MQTT-Gear-Server/OU=MQTT Broker/CN=$MQTT_BROKER_IP"

# 創建擴展文件
print_info "創建憑證擴展配置..."
cat > server.ext << EOF
[v3_ext]
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = mqtt-broker
DNS.3 = *.local
DNS.4 = mosquitto
DNS.5 = ${MQTT_BROKER_IP}
IP.1 = 127.0.0.1
IP.2 = ::1
IP.3 = ${MQTT_BROKER_IP}
IP.4 = 0.0.0.0
IP.5 = 172.17.0.1
IP.6 = 192.168.0.1
EOF

# 用 CA 簽署服務器憑證
print_info "簽署服務器憑證..."
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out server.crt -days 365 -extensions v3_ext -extfile server.ext

# 驗證憑證
print_info "驗證憑證..."
if openssl verify -CAfile ca.crt server.crt > /dev/null 2>&1; then
    print_success "憑證驗證通過"
else
    print_warning "憑證驗證失敗，但可能仍可使用"
fi

# 設置文件權限
print_info "設置文件權限..."
chmod 600 server.key ca.key
chmod 644 server.crt ca.crt

# 清理臨時文件
rm -f server.csr ca.srl server.ext

print_success "TLS 憑證生成完成"
echo ""

# 顯示憑證信息
print_info "憑證信息："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "CA 憑證："
openssl x509 -in ca.crt -text -noout | grep -E "(Subject:|Validity|Not After)" | sed 's/^/  /'
echo ""
echo "服務器憑證："
openssl x509 -in server.crt -text -noout | grep -E "(Subject:|Validity|Not After|DNS:|IP Address:)" | sed 's/^/  /'
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_info "憑證文件位置："
echo "  CA 憑證: $(pwd)/ca.crt"
echo "  CA 私鑰: $(pwd)/ca.key"
echo "  服務器憑證: $(pwd)/server.crt"
echo "  服務器私鑰: $(pwd)/server.key"
echo ""

print_warning "請妥善保管 CA 私鑰 (ca.key) 和服務器私鑰 (server.key)"
print_info "憑證已配置支持以下域名/IP："
echo "  - localhost"
echo "  - mqtt-broker" 
echo "  - mosquitto"
echo "  - ${MQTT_BROKER_IP}"
echo "  - 127.0.0.1"
echo "  - 0.0.0.0"

cd ..
echo ""
print_success "🔒 憑證生成完成！現在可以使用 TLS 加密連接"
