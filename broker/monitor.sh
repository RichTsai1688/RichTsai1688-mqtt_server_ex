#!/bin/bash

# MQTT Gear Server - Docker 狀態監控腳本
# 提供詳細的容器狀態、資源使用和健康檢查

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 函數定義
print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                    🐳 MQTT Docker 監控面板                    ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo -e "${CYAN}▶ $1${NC}"
    echo "----------------------------------------"
}

print_status() {
    local status=$1
    local service=$2
    
    if [[ "$status" == *"Up"* ]]; then
        echo -e "  ${GREEN}✅ $service${NC}"
    elif [[ "$status" == *"Exit"* ]]; then
        echo -e "  ${RED}❌ $service (已退出)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  $service (未知狀態)${NC}"
    fi
}

# 檢查服務狀態
check_services() {
    print_section "📊 服務狀態"
    
    if [ -f "docker-compose.yml" ]; then
        echo "開發環境:"
        while IFS= read -r line; do
            if [[ $line == *"mosquitto"* ]]; then
                print_status "$line" "MQTT Broker"
            fi
        done < <(docker-compose ps 2>/dev/null || echo "未運行")
        echo ""
    fi
    
    if [ -f "docker-compose.prod.yml" ]; then
        echo "生產環境:"
        while IFS= read -r line; do
            case $line in
                *"mosquitto"*) print_status "$line" "MQTT Broker" ;;
                *"prometheus"*) print_status "$line" "Prometheus" ;;
                *"grafana"*) print_status "$line" "Grafana" ;;
                *"mqtt-exporter"*) print_status "$line" "MQTT Exporter" ;;
                *"redis"*) print_status "$line" "Redis" ;;
                *"nginx"*) print_status "$line" "Nginx" ;;
                *"backup"*) print_status "$line" "Backup Service" ;;
            esac
        done < <(docker-compose -f docker-compose.prod.yml ps 2>/dev/null || echo "未運行")
    fi
    
    echo ""
}

# 檢查資源使用
check_resources() {
    print_section "💻 資源使用情況"
    
    local containers=$(docker ps --filter "name=mosquitto" --filter "name=mqtt-" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null)
    
    if [ -n "$containers" ]; then
        echo "容器資源統計:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" \
            $(docker ps --filter "name=mosquitto" --filter "name=mqtt-" --format "{{.Names}}" | tr '\n' ' ') 2>/dev/null || \
            echo "  無法獲取資源統計信息"
    else
        echo "  沒有運行中的 MQTT 相關容器"
    fi
    
    echo ""
}

# 檢查端口狀態
check_ports() {
    print_section "🌐 端口狀態"
    
    local ports=("1883:MQTT" "8883:MQTT TLS" "9001:WebSocket" "3000:Grafana" "9090:Prometheus" "9234:MQTT Metrics")
    
    for port_info in "${ports[@]}"; do
        IFS=":" read -r port service <<< "$port_info"
        if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "  ${GREEN}✅ $service ($port)${NC}"
        else
            echo -e "  ${RED}❌ $service ($port) - 未監聽${NC}"
        fi
    done
    
    echo ""
}

# 測試 MQTT 連接
test_mqtt_connection() {
    print_section "🔌 MQTT 連接測試"
    
    if ! command -v mosquitto_pub &> /dev/null; then
        echo -e "  ${YELLOW}⚠️  mosquitto_pub 未安裝，跳過連接測試${NC}"
        echo "     安裝: brew install mosquitto (macOS) 或 apt-get install mosquitto-clients (Ubuntu)"
        echo ""
        return
    fi
    
    # 測試匿名連接 (如果允許)
    if timeout 5 mosquitto_pub -h localhost -p 1883 -t test/monitor -m "test" -q 2>/dev/null; then
        echo -e "  ${GREEN}✅ 匿名連接 (1883)${NC}"
    else
        echo -e "  ${RED}❌ 匿名連接被拒絕 (1883) - 正常，需要認證${NC}"
    fi
    
    # 測試 TLS 連接
    if [ -f "certs/ca.crt" ]; then
        if timeout 5 mosquitto_pub -h localhost -p 8883 --cafile certs/ca.crt -t test/tls -m "tls_test" -q 2>/dev/null; then
            echo -e "  ${GREEN}✅ TLS 連接 (8883)${NC}"
        else
            echo -e "  ${RED}❌ TLS 連接失敗 (8883) - 需要認證${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️  TLS 憑證不存在，跳過 TLS 測試${NC}"
    fi
    
    echo ""
}

# 檢查日誌
check_logs() {
    print_section "📝 最新日誌"
    
    if [ -f "log/mosquitto.log" ]; then
        echo "Mosquitto 日誌 (最新 5 行):"
        tail -5 log/mosquitto.log 2>/dev/null || echo "  無法讀取日誌文件"
    else
        echo "Mosquitto 日誌文件不存在"
    fi
    
    echo ""
    
    # Docker 容器日誌
    local mosquitto_container=$(docker ps --filter "name=mosquitto" --format "{{.Names}}" | head -1)
    if [ -n "$mosquitto_container" ]; then
        echo "Docker 容器日誌 (最新 3 行):"
        docker logs --tail 3 "$mosquitto_container" 2>/dev/null || echo "  無法獲取容器日誌"
    fi
    
    echo ""
}

# 檢查配置文件
check_config() {
    print_section "⚙️ 配置檢查"
    
    local issues=0
    
    # 檢查必要文件
    local required_files=("mosquitto.conf" "acl" "passwd")
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "  ${GREEN}✅ $file${NC}"
        else
            echo -e "  ${RED}❌ $file - 缺失${NC}"
            ((issues++))
        fi
    done
    
    # 檢查 TLS 憑證
    if [ -f "certs/server.crt" ] && [ -f "certs/server.key" ] && [ -f "certs/ca.crt" ]; then
        echo -e "  ${GREEN}✅ TLS 憑證完整${NC}"
        
        # 檢查憑證有效期
        local cert_expiry=$(openssl x509 -in certs/server.crt -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ -n "$cert_expiry" ]; then
            local expiry_epoch=$(date -d "$cert_expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$cert_expiry" +%s 2>/dev/null)
            local current_epoch=$(date +%s)
            local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            if [ $days_left -lt 30 ]; then
                echo -e "  ${YELLOW}⚠️  TLS 憑證將在 $days_left 天後過期${NC}"
            else
                echo -e "  ${GREEN}✅ TLS 憑證有效 ($days_left 天)${NC}"
            fi
        fi
    else
        echo -e "  ${YELLOW}⚠️  TLS 憑證不完整${NC}"
    fi
    
    # 檢查數據目錄權限
    if [ -d "data" ] && [ -d "log" ]; then
        local data_owner=$(stat -c '%U:%G' data 2>/dev/null || stat -f '%Su:%Sg' data 2>/dev/null)
        if [[ "$data_owner" == "1883:1883" ]] || [[ "$data_owner" == *"mosquitto"* ]]; then
            echo -e "  ${GREEN}✅ 數據目錄權限正確${NC}"
        else
            echo -e "  ${YELLOW}⚠️  數據目錄權限可能不正確 ($data_owner)${NC}"
            echo "     建議執行: sudo chown -R 1883:1883 data log"
        fi
    fi
    
    if [ $issues -eq 0 ]; then
        echo -e "  ${GREEN}✅ 配置檢查通過${NC}"
    else
        echo -e "  ${RED}❌ 發現 $issues 個配置問題${NC}"
    fi
    
    echo ""
}

# 顯示快速命令
show_commands() {
    print_section "🚀 快速命令"
    
    echo "容器管理:"
    echo "  docker-compose up -d                    # 啟動開發環境"
    echo "  docker-compose -f docker-compose.prod.yml up -d  # 啟動生產環境"
    echo "  docker-compose down                     # 停止服務"
    echo "  docker-compose restart mosquitto       # 重啟 MQTT Broker"
    echo ""
    echo "監控和調試:"
    echo "  docker-compose logs -f mosquitto        # 查看實時日誌"
    echo "  docker exec -it mosquitto-mqtt-broker sh   # 進入容器"
    echo "  mosquitto_sub -h localhost -p 1883 -t '#' -v   # 監聽所有消息"
    echo ""
    echo "管理命令:"
    echo "  ./deploy.sh dev                         # 部署開發環境"
    echo "  ./deploy.sh prod                        # 部署生產環境"
    echo "  ./deploy.sh status                      # 檢查狀態"
    echo "  ./deploy.sh cleanup                     # 清理資源"
    echo ""
}

# 主函數
main() {
    clear
    print_header
    
    case "${1:-all}" in
        "services"|"status")
            check_services
            ;;
        "resources"|"res")
            check_resources
            ;;
        "ports"|"network")
            check_ports
            ;;
        "connection"|"conn"|"test")
            test_mqtt_connection
            ;;
        "logs"|"log")
            check_logs
            ;;
        "config"|"conf")
            check_config
            ;;
        "commands"|"cmd"|"help")
            show_commands
            ;;
        "all")
            check_services
            check_resources
            check_ports
            test_mqtt_connection
            check_config
            check_logs
            show_commands
            ;;
        "watch")
            # 監控模式 - 每 5 秒刷新
            while true; do
                clear
                print_header
                check_services
                check_resources
                check_ports
                echo -e "${CYAN}🔄 自動刷新中... (Ctrl+C 退出)${NC}"
                sleep 5
            done
            ;;
        *)
            echo "用法: $0 [all|services|resources|ports|connection|config|logs|commands|watch]"
            echo ""
            echo "選項:"
            echo "  all          顯示所有信息 (默認)"
            echo "  services     服務狀態"
            echo "  resources    資源使用"
            echo "  ports        端口狀態" 
            echo "  connection   MQTT 連接測試"
            echo "  config       配置檢查"
            echo "  logs         最新日誌"
            echo "  commands     快速命令"
            echo "  watch        監控模式 (自動刷新)"
            exit 1
            ;;
    esac
    
    echo -e "${BLUE}💡 提示: 使用 '$0 watch' 進入實時監控模式${NC}"
}

# 執行主函數
main "$@"
