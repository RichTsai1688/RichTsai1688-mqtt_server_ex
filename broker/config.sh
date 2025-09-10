#!/bin/bash

# MQTT Gear Server 配置工具
# 用於設置 IP 地址和其他系統參數

set -e

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

# 顯示當前配置
show_current_config() {
    print_info "當前配置:"
    if [ -f ".env" ]; then
        echo ""
        while IFS= read -r line; do
            if [[ $line =~ ^[A-Z] ]]; then
                echo "  $line"
            fi
        done < .env
    else
        print_warning "尚未找到 .env 配置文件"
    fi
    echo ""
}

# 設置 MQTT Broker IP
set_broker_ip() {
    echo -e "${BLUE}🌐 設置 MQTT Broker IP 地址${NC}"
    echo ""
    
    # 獲取當前 IP
    local current_ip=""
    if [ -f ".env" ]; then
        current_ip=$(grep "^MQTT_BROKER_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
    fi
    
    if [ -n "$current_ip" ]; then
        echo "當前 IP: $current_ip"
    else
        echo "當前 IP: 未設置"
    fi
    
    echo ""
    echo "常用選項:"
    echo "  1) localhost (127.0.0.1) - 本機測試"
    echo "  2) 140.134.60.218 - 您指定的伺服器"
    echo "  3) 0.0.0.0 - 監聽所有介面"
    echo "  4) 自訂 IP 地址"
    echo ""
    
    read -p "請選擇 (1-4) 或直接輸入 IP 地址: " choice
    
    case $choice in
        1)
            new_ip="127.0.0.1"
            ;;
        2)
            new_ip="140.134.60.218"
            ;;
        3)
            new_ip="0.0.0.0"
            ;;
        4)
            read -p "請輸入 IP 地址: " new_ip
            ;;
        *)
            # 檢查是否為有效的 IP 地址格式
            if [[ $choice =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                new_ip="$choice"
            else
                print_error "無效的選項或 IP 地址格式"
                return 1
            fi
            ;;
    esac
    
    # 驗證 IP 地址格式
    if [[ ! $new_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$new_ip" != "localhost" ]; then
        print_error "無效的 IP 地址格式"
        return 1
    fi
    
    # 更新 .env 文件
    update_env_var "MQTT_BROKER_IP" "$new_ip"
    print_success "MQTT Broker IP 已設置為: $new_ip"
}

# 設置端口
set_ports() {
    echo -e "${BLUE}🔌 設置端口配置${NC}"
    echo ""
    
    # 讀取當前端口
    local current_mqtt_port=$(get_env_var "MQTT_PORT" "4883")
    local current_tls_port=$(get_env_var "MQTT_TLS_PORT" "4884")
    local current_ws_port=$(get_env_var "MQTT_WS_PORT" "9021")
    
    echo "當前端口配置:"
    echo "  MQTT: $current_mqtt_port"
    echo "  MQTT TLS: $current_tls_port"
    echo "  WebSocket: $current_ws_port"
    echo ""
    
    echo "端口配置選項:"
    echo "  1) 使用當前配置"
    echo "  2) 標準端口 (1883, 8883, 9001)"
    echo "  3) 自訂端口配置"
    echo ""
    
    read -p "請選擇 (1-3): " port_choice
    
    case $port_choice in
        1)
            print_info "保持當前端口配置"
            ;;
        2)
            update_env_var "MQTT_PORT" "1883"
            update_env_var "MQTT_TLS_PORT" "8883"
            update_env_var "MQTT_WS_PORT" "9001"
            print_success "已設置為標準端口"
            ;;
        3)
            read -p "MQTT 端口 [$current_mqtt_port]: " mqtt_port
            read -p "MQTT TLS 端口 [$current_tls_port]: " tls_port
            read -p "WebSocket 端口 [$current_ws_port]: " ws_port
            
            mqtt_port=${mqtt_port:-$current_mqtt_port}
            tls_port=${tls_port:-$current_tls_port}
            ws_port=${ws_port:-$current_ws_port}
            
            update_env_var "MQTT_PORT" "$mqtt_port"
            update_env_var "MQTT_TLS_PORT" "$tls_port" 
            update_env_var "MQTT_WS_PORT" "$ws_port"
            print_success "端口配置已更新"
            ;;
        *)
            print_error "無效選項"
            return 1
            ;;
    esac
}

# 設置用戶名
set_users() {
    echo -e "${BLUE}👤 設置用戶配置${NC}"
    echo ""
    
    local current_a_user=$(get_env_var "MQTT_A_USER" "A_user")
    local current_b_user=$(get_env_var "MQTT_B_USER" "B_user")
    local current_monitor_user=$(get_env_var "MQTT_MONITOR_USER" "monitor_user")
    
    echo "當前用戶配置:"
    echo "  A 端用戶: $current_a_user"
    echo "  B 端用戶: $current_b_user" 
    echo "  監控用戶: $current_monitor_user"
    echo ""
    
    read -p "是否要修改用戶名? (y/N): " modify_users
    
    if [[ $modify_users =~ ^[Yy]$ ]]; then
        read -p "A 端用戶名 [$current_a_user]: " a_user
        read -p "B 端用戶名 [$current_b_user]: " b_user
        read -p "監控用戶名 [$current_monitor_user]: " monitor_user
        
        a_user=${a_user:-$current_a_user}
        b_user=${b_user:-$current_b_user}
        monitor_user=${monitor_user:-$current_monitor_user}
        
        update_env_var "MQTT_A_USER" "$a_user"
        update_env_var "MQTT_B_USER" "$b_user"
        update_env_var "MQTT_MONITOR_USER" "$monitor_user"
        
        print_success "用戶配置已更新"
        print_warning "請記得更新密碼文件: ./deploy.sh 會重新生成密碼"
    else
        print_info "保持當前用戶配置"
    fi
}

# 獲取環境變數值
get_env_var() {
    local var_name=$1
    local default_value=$2
    
    if [ -f ".env" ]; then
        grep "^${var_name}=" .env 2>/dev/null | cut -d'=' -f2 || echo "$default_value"
    else
        echo "$default_value"
    fi
}

# 更新環境變數
update_env_var() {
    local var_name=$1
    local var_value=$2
    
    # 確保 .env 文件存在
    if [ ! -f ".env" ]; then
        cp .env.template .env 2>/dev/null || touch .env
    fi
    
    # 檢查變數是否已存在
    if grep -q "^${var_name}=" .env; then
        # 更新現有變數
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^${var_name}=.*/${var_name}=${var_value}/" .env
        else
            sed -i "s/^${var_name}=.*/${var_name}=${var_value}/" .env
        fi
    else
        # 添加新變數
        echo "${var_name}=${var_value}" >> .env
    fi
}

# 生成客戶端配置文件
generate_client_configs() {
    print_info "生成客戶端配置文件..."
    
    local broker_ip=$(get_env_var "MQTT_BROKER_IP" "140.134.60.218")
    local mqtt_port=$(get_env_var "MQTT_PORT" "4883")
    local tls_port=$(get_env_var "MQTT_TLS_PORT" "4884")
    
    # Python 客戶端配置
    cat > ../client-python-A/config.env << EOF
# Python A 客戶端配置
export MQTT_BROKER_IP=${broker_ip}
export MQTT_PORT=${mqtt_port}
export MQTT_TLS_PORT=${tls_port}
export MQTT_A_USER=$(get_env_var "MQTT_A_USER" "A_user")
export MQTT_CLIENT_ID=$(get_env_var "MQTT_CLIENT_ID" "id1")
EOF

    # C# 客戶端配置  
    cat > ../client-csharp-B/appsettings.json << EOF
{
  "MqttSettings": {
    "BrokerIP": "${broker_ip}",
    "Port": ${mqtt_port},
    "TlsPort": ${tls_port},
    "ClientId": "$(get_env_var "MQTT_CLIENT_ID" "id1")",
    "BUser": "$(get_env_var "MQTT_B_USER" "B_user")"
  }
}
EOF

    print_success "客戶端配置文件已生成"
}

# 測試連接
test_connection() {
    print_info "測試 MQTT 連接..."
    
    local broker_ip=$(get_env_var "MQTT_BROKER_IP" "140.134.60.218")
    local mqtt_port=$(get_env_var "MQTT_PORT" "4883")
    
    if command -v mosquitto_pub &> /dev/null; then
        if mosquitto_pub -h $broker_ip -p $mqtt_port -t test/config -m "config_test" -q 2>/dev/null; then
            print_success "連接測試成功 ($broker_ip:$mqtt_port)"
        else
            print_warning "連接測試失敗 - 可能需要啟動 MQTT Broker 或配置認證"
        fi
    else
        print_warning "mosquitto_pub 未安裝，無法測試連接"
    fi
}

# 主選單
show_menu() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}              🐳 MQTT Gear Server 配置工具                  ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    show_current_config
    
    echo "配置選項:"
    echo "  1) 設置 MQTT Broker IP 地址"
    echo "  2) 設置端口配置"
    echo "  3) 設置用戶配置"
    echo "  4) 生成客戶端配置文件"
    echo "  5) 測試連接"
    echo "  6) 重置為預設值"
    echo "  7) 退出"
    echo ""
}

# 重置配置
reset_config() {
    print_warning "這將重置所有配置為預設值"
    read -p "確定要繼續嗎? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        cp .env.template .env 2>/dev/null || {
            # 如果沒有模板，創建默認配置
            cat > .env << 'EOF'
# MQTT Gear Server 環境變數配置
MQTT_BROKER_IP=140.134.60.218
MQTT_PORT=4883
MQTT_TLS_PORT=4884
MQTT_WS_PORT=9021
MQTT_A_USER=A_user
MQTT_B_USER=B_user
MQTT_MONITOR_USER=monitor_user
MQTT_CLIENT_ID=id1
TIMEZONE=Asia/Taipei
EOF
        }
        print_success "配置已重置為預設值"
    fi
}

# 主函數
main() {
    # 確保在 broker 目錄中執行
    if [ ! -f "docker-compose.yml" ]; then
        print_error "請在 broker 目錄中執行此腳本"
        exit 1
    fi
    
    while true; do
        show_menu
        read -p "請選擇 (1-7): " choice
        
        case $choice in
            1)
                set_broker_ip
                read -p "按 Enter 繼續..."
                ;;
            2)
                set_ports
                read -p "按 Enter 繼續..."
                ;;
            3)
                set_users
                read -p "按 Enter 繼續..."
                ;;
            4)
                generate_client_configs
                read -p "按 Enter 繼續..."
                ;;
            5)
                test_connection
                read -p "按 Enter 繼續..."
                ;;
            6)
                reset_config
                read -p "按 Enter 繼續..."
                ;;
            7)
                print_info "配置完成!"
                echo ""
                echo "下一步:"
                echo "  ./deploy.sh dev    # 部署開發環境"
                echo "  ./deploy.sh prod   # 部署生產環境"
                echo "  ./monitor.sh       # 監控系統狀態"
                exit 0
                ;;
            *)
                print_error "無效選項，請重新選擇"
                read -p "按 Enter 繼續..."
                ;;
        esac
    done
}

# 執行主函數
main "$@"
