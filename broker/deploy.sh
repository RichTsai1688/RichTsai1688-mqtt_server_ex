#!/bin/bash

# MQTT Gear Server - Docker 自動部署腳本
# 支持開發和生產環境部署

set -e  # 遇到錯誤立即退出

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 函數定義
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

# 載入環境變數
load_environment() {
    if [ -f ".env" ]; then
        source .env
        print_info "已載入 .env 配置文件"
    else
        print_warning ".env 文件未找到，使用預設值"
    fi
    
    # 設置默認值
    MQTT_BROKER_IP=${MQTT_BROKER_IP:-140.134.60.218}
    MQTT_PORT=${MQTT_PORT:-4883}
    MQTT_TLS_PORT=${MQTT_TLS_PORT:-4884}
    MQTT_WS_PORT=${MQTT_WS_PORT:-9021}
    MQTT_A_USER=${MQTT_A_USER:-A_user}
    MQTT_B_USER=${MQTT_B_USER:-B_user}
    MQTT_MONITOR_USER=${MQTT_MONITOR_USER:-monitor_user}
    MQTT_CLIENT_ID=${MQTT_CLIENT_ID:-id1}
    PROMETHEUS_PORT=${PROMETHEUS_PORT:-9090}
    GRAFANA_PORT=${GRAFANA_PORT:-3000}
    MQTT_EXPORTER_PORT=${MQTT_EXPORTER_PORT:-9234}
}

# 檢測可用的 Docker Compose 命令
get_docker_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null 2>&1; then
        echo "docker compose"
    else
        return 1
    fi
}

# 檢查 Docker 環境
check_docker() {
    print_info "檢查 Docker 環境..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安裝，請先安裝 Docker"
        exit 1
    fi
    
    # 檢測 Docker Compose 命令並設為全域變數
    if ! DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd); then
        print_error "Docker Compose 未安裝或不可用"
        print_info "請安裝 Docker Compose 或確保使用 Docker Desktop"
        exit 1
    fi
    export DOCKER_COMPOSE_CMD
    
    if ! docker info &> /dev/null; then
        print_error "Docker 服務未運行，請啟動 Docker 服務"
        exit 1
    fi
    
    print_success "Docker 環境檢查通過 (使用: $DOCKER_COMPOSE_CMD)"
}

# 清理網路衝突
cleanup_network_conflicts() {
    print_info "檢查並清理網路衝突..."
    
    # 獲取專案名稱
    local project_name=$(basename "$(pwd)")
    
    # 清理可能衝突的網路
    local networks_to_check=(
        "${project_name}_mqtt-network"
        "broker_mqtt-network"
        "mqtt-gear-server_mqtt-network"
    )
    
    for network in "${networks_to_check[@]}"; do
        if docker network ls | grep -q "$network"; then
            print_warning "發現衝突網路: $network，正在清理..."
            docker network rm "$network" 2>/dev/null || true
        fi
    done
    
    # 清理未使用的網路
    docker network prune -f >/dev/null 2>&1 || true
    
    print_info "網路清理完成"
}

# 創建必要目錄
create_directories() {
    print_info "創建必要目錄..."
    
    local dirs=(
        "data"
        "log" 
        "certs"
        "scripts"
        "backup"
        "monitoring/prometheus"
        "monitoring/grafana"
        "nginx/ssl"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        print_info "  創建目錄: $dir"
    done
    
    print_success "目錄創建完成"
}

# 生成密碼文件
generate_passwords() {
    if [ -f "passwd" ]; then
        print_warning "密碼文件已存在，跳過生成"
        return
    fi
    
    print_info "生成 MQTT 用戶密碼文件..."
    
    if command -v mosquitto_passwd &> /dev/null; then
        # 使用本地 mosquitto_passwd
        print_info "使用本地 mosquitto_passwd 工具"
        echo "請為 A_user 設置密碼:"
        mosquitto_passwd -c passwd A_user
        echo "請為 B_user 設置密碼:"
        mosquitto_passwd passwd B_user
        
        # 添加監控用戶
        echo "請為 monitor_user 設置密碼:"
        mosquitto_passwd passwd monitor_user
    else
        # 使用 Docker 容器
        print_info "使用 Docker 容器生成密碼"
        echo "請為 A_user 設置密碼:"
        docker run -it --rm -v "$(pwd)":/data eclipse-mosquitto:2 \
            mosquitto_passwd -c /data/passwd A_user
        
        echo "請為 B_user 設置密碼:"
        docker run -it --rm -v "$(pwd)":/data eclipse-mosquitto:2 \
            mosquitto_passwd /data/passwd B_user
            
        echo "請為 monitor_user 設置密碼:"
        docker run -it --rm -v "$(pwd)":/data eclipse-mosquitto:2 \
            mosquitto_passwd /data/passwd monitor_user
    fi
    
    chmod 644 passwd
    print_success "密碼文件生成完成"
}

# 生成 TLS 憑證
generate_certificates() {
    if [ -f "certs/server.crt" ] && [ -f "certs/ca.crt" ]; then
        print_warning "TLS 憑證已存在，跳過生成"
        return
    fi
    
    print_info "生成 TLS 自簽名憑證..."
    
    # 使用獨立的憑證生成腳本
    if [ -f "generate_certs.sh" ]; then
        if ./generate_certs.sh; then
            return
        else
            print_warning "獨立憑證腳本執行失敗，嘗試內建方法..."
        fi
    fi
    
    # 內建憑證生成方法
    mkdir -p certs
    cd certs
    
    # 生成 CA 私鑰
    openssl genrsa -out ca.key 4096
    
    # 生成 CA 根憑證
    openssl req -new -x509 -key ca.key -out ca.crt -days 365 \
        -subj "/C=TW/ST=Taiwan/L=Taipei/O=MQTT-Gear-Server/CN=MQTT-CA"
    
    # 生成服務器私鑰
    openssl genrsa -out server.key 4096
    
    # 生成服務器憑證請求
    openssl req -new -key server.key -out server.csr \
        -subj "/C=TW/ST=Taiwan/L=Taipei/O=MQTT-Gear-Server/CN=localhost"
    
    # 創建擴展文件 (支持多域名和 IP)
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
IP.1 = 127.0.0.1
IP.2 = ::1
IP.3 = ${MQTT_BROKER_IP}
IP.4 = 0.0.0.0
EOF

    # 用 CA 簽署服務器憑證
    if openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
        -CAcreateserial -out server.crt -days 365 -extensions v3_ext -extfile server.ext; then
        
        # 設置文件權限
        chmod 600 server.key ca.key
        chmod 644 server.crt ca.crt

        # 清理臨時文件
        rm -f server.csr ca.srl server.ext

        cd ..
        print_success "TLS 憑證生成完成"
    else
        print_error "憑證生成失敗"
        cd ..
        print_warning "TLS 功能可能無法使用，但 MQTT 基本功能仍可正常運行"
    fi
}

# 創建監控配置
create_monitoring_configs() {
    print_info "創建監控配置文件..."
    
    # Prometheus 配置
    cat > prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'mqtt-exporter'
    static_configs:
      - targets: ['mqtt-exporter:9234']
    scrape_interval: 30s
    
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
      
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
EOF

    # Grafana 數據源配置
    mkdir -p grafana/datasources
    cat > grafana/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

    # Redis 配置
    cat > redis/redis.conf << 'EOF'
bind 0.0.0.0
port 6379
timeout 300
keepalive 60
maxmemory 256mb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
EOF

    print_success "監控配置創建完成"
}

# 創建備份腳本
create_backup_script() {
    print_info "創建備份腳本..."
    
    cat > scripts/backup.sh << 'EOF'
#!/bin/ash

# MQTT 數據備份腳本

BACKUP_DIR="/backup"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="mqtt_backup_${DATE}.tar.gz"

echo "開始備份 MQTT 數據..."

# 創建備份
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}" \
    -C /source data logs

# 保留最近 7 天的備份
find "${BACKUP_DIR}" -name "mqtt_backup_*.tar.gz" -mtime +7 -delete

echo "備份完成: ${BACKUP_NAME}"

# 添加到 crontab (每天凌晨 2 點執行)
# 0 2 * * * /backup.sh >> /var/log/backup.log 2>&1
EOF

    chmod +x scripts/backup.sh
    print_success "備份腳本創建完成"
}

# 部署函數
deploy_development() {
    print_info "部署開發環境..."
    
    # 嘗試啟動服務，如果失敗則清理並重試
    if ! $DOCKER_COMPOSE_CMD up -d; then
        print_warning "首次部署失敗，清理衝突資源後重試..."
        $DOCKER_COMPOSE_CMD down --remove-orphans 2>/dev/null || true
        cleanup_network_conflicts
        sleep 2
        
        print_info "重試部署..."
        if ! $DOCKER_COMPOSE_CMD up -d; then
            print_error "部署失敗，請檢查 Docker 日誌"
            print_info "可以嘗試: docker compose logs"
            exit 1
        fi
    fi
    
    print_success "開發環境部署完成"
    print_info "MQTT Broker: ${MQTT_BROKER_IP}:${MQTT_PORT} (非加密)"
    print_info "MQTT TLS: ${MQTT_BROKER_IP}:${MQTT_TLS_PORT} (加密)" 
    print_info "WebSocket: ${MQTT_BROKER_IP}:${MQTT_WS_PORT:-9021}"
}

deploy_production() {
    print_info "部署生產環境..."
    
    create_monitoring_configs
    create_backup_script
    
    # 嘗試啟動服務，如果失敗則清理並重試
    if ! $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml up -d; then
        print_warning "首次部署失敗，清理衝突資源後重試..."
        $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml down --remove-orphans 2>/dev/null || true
        cleanup_network_conflicts
        sleep 2
        
        print_info "重試部署..."
        if ! $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml up -d; then
            print_error "生產環境部署失敗，請檢查 Docker 日誌"
            print_info "可以嘗試: docker compose -f docker-compose.prod.yml logs"
            exit 1
        fi
    fi
    
    print_success "生產環境部署完成"
    print_info "MQTT Broker: ${MQTT_BROKER_IP}:${MQTT_PORT} (非加密)"
    print_info "MQTT TLS: ${MQTT_BROKER_IP}:${MQTT_TLS_PORT} (加密)"
    print_info "WebSocket: ${MQTT_BROKER_IP}:${MQTT_WS_PORT:-9021}"
    print_info "Grafana: http://${MQTT_BROKER_IP}:${GRAFANA_PORT:-3000} (admin/${GRAFANA_ADMIN_PASSWORD:-admin123})"
    print_info "Prometheus: http://${MQTT_BROKER_IP}:${PROMETHEUS_PORT:-9090}"
    print_info "MQTT Metrics: http://${MQTT_BROKER_IP}:${MQTT_METRICS_PORT:-9234}/metrics"
}

# 顯示狀態
show_status() {
    print_info "檢查服務狀態..."
    
    if [ "$1" = "prod" ]; then
        $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml ps
    else
        $DOCKER_COMPOSE_CMD ps
    fi
    
    echo ""
    print_info "健康檢查:"
    
    # 測試 MQTT 連接
    if command -v mosquitto_pub &> /dev/null; then
        if mosquitto_pub -h ${MQTT_BROKER_IP} -p ${MQTT_PORT} -t test/deploy -m "deployment_test" -u A_user -P "$(read -sp 'A_user密碼: ' pwd; echo $pwd)" 2>/dev/null; then
            print_success "MQTT 連接正常 (${MQTT_BROKER_IP}:${MQTT_PORT})"
        else
            print_warning "MQTT 連接測試失敗 (${MQTT_BROKER_IP}:${MQTT_PORT})"
        fi
    fi
}

# 清理函數
cleanup() {
    print_warning "清理 Docker 資源..."
    
    if [ "$1" = "prod" ]; then
        $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml down -v
    else
        $DOCKER_COMPOSE_CMD down -v
    fi
    
    # 清理未使用的 Docker 資源
    docker system prune -f
    
    print_success "清理完成"
}

# 主函數
main() {
    echo "🐳 MQTT Gear Server - Docker 部署工具"
    echo "======================================"
    
    # 載入環境配置
    load_environment
    
    # 解析命令行參數
    case "${1:-dev}" in
        "dev"|"development")
            ENV="dev"
            ;;
        "prod"|"production")
            ENV="prod"
            ;;
        "status")
            load_environment
            check_docker
            show_status "${2:-dev}"
            exit 0
            ;;
        "cleanup"|"clean")
            load_environment
            check_docker
            cleanup "${2:-dev}"
            exit 0
            ;;
        "help"|"-h"|"--help")
            echo "用法: $0 [dev|prod|status|cleanup|help]"
            echo ""
            echo "選項:"
            echo "  dev         部署開發環境 (默認)"
            echo "  prod        部署生產環境 (包含監控)"
            echo "  status      顯示服務狀態"
            echo "  cleanup     清理 Docker 資源"
            echo "  help        顯示此幫助信息"
            exit 0
            ;;
        *)
            print_error "未知選項: $1"
            echo "使用 '$0 help' 查看幫助"
            exit 1
            ;;
    esac
    
    # 執行部署流程
    check_docker
    cleanup_network_conflicts
    create_directories
    generate_passwords
    generate_certificates
    
    if [ "$ENV" = "prod" ]; then
        deploy_production
    else
        deploy_development
    fi
    
    echo ""
    show_status "$ENV"
    
    echo ""
    print_success "🎉 部署完成!"
    
    if [ "$ENV" = "prod" ]; then
        print_info "生產環境已啟動，請查看監控面板確認服務狀態"
    else
        print_info "開發環境已啟動，可以開始測試 MQTT 連接"
    fi
}

# 執行主函數
main "$@"
