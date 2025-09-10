#!/bin/bash

# MQTT Gear Server - 網路診斷工具

echo "🔍 MQTT Gear Server 網路診斷"
echo "============================"
echo ""

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

# 檢查 Docker 網路
print_info "檢查 Docker 網路狀態..."
echo "現有網路:"
docker network ls | grep -E "(NETWORK|bridge|host|mqtt)" || echo "  無相關網路"
echo ""

# 檢查 IP 範圍衝突
print_info "檢查常見 IP 範圍使用情況..."

common_ranges=(
    "172.16.0.0/16"
    "172.17.0.0/16"
    "172.18.0.0/16"
    "172.19.0.0/16"
    "172.20.0.0/16"
    "172.21.0.0/16"
    "172.28.0.0/16"
    "172.29.0.0/16"
)

for range in "${common_ranges[@]}"; do
    network_name=$(docker network ls --format "table {{.Name}}" --filter "driver=bridge" | tail -n +2 | while read net; do
        if [ "$net" != "bridge" ]; then
            subnet=$(docker network inspect "$net" 2>/dev/null | jq -r '.[].IPAM.Config[].Subnet' 2>/dev/null | head -1)
            if [ "$subnet" = "$range" ]; then
                echo "$net"
                break
            fi
        fi
    done)
    
    if [ -n "$network_name" ]; then
        print_warning "$range 已被網路 '$network_name' 使用"
    else
        print_success "$range 可用"
    fi
done

echo ""

# 檢查系統網路介面
print_info "檢查系統網路介面..."
if command -v ip &> /dev/null; then
    ip route show | grep -E "172\." | head -5
elif command -v ifconfig &> /dev/null; then
    ifconfig | grep -E "inet.*172\." | head -5
else
    print_warning "無法檢查系統網路介面"
fi

echo ""

# 檢查 MQTT 相關容器
print_info "檢查 MQTT 相關容器..."
mqtt_containers=$(docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -i mqtt || echo "無 MQTT 容器")
if [ "$mqtt_containers" = "無 MQTT 容器" ]; then
    print_info "未發現 MQTT 容器"
else
    echo "$mqtt_containers"
fi

echo ""

# 清理建議
print_info "清理建議:"
echo "  1. 清理未使用的網路: docker network prune -f"
echo "  2. 停止衝突的容器: docker compose down"
echo "  3. 強制重建網路: docker compose down && docker network rm broker_mqtt-network"
echo "  4. 檢查系統路由: ip route (Linux) 或 route -n (macOS)"

echo ""

# 自動清理選項
read -p "是否要自動清理未使用的 Docker 資源? (y/N): " cleanup_choice

if [[ $cleanup_choice =~ ^[Yy]$ ]]; then
    print_info "正在清理 Docker 資源..."
    
    # 停止所有 MQTT 相關容器
    docker ps -q --filter "name=mqtt" | xargs -r docker stop 2>/dev/null || true
    docker ps -q --filter "name=mosquitto" | xargs -r docker stop 2>/dev/null || true
    
    # 清理網路
    docker network prune -f
    
    # 清理容器
    docker container prune -f
    
    # 清理卷（謹慎）
    read -p "是否要清理未使用的 Docker 卷？這會刪除未使用的數據 (y/N): " volume_cleanup
    if [[ $volume_cleanup =~ ^[Yy]$ ]]; then
        docker volume prune -f
    fi
    
    print_success "清理完成"
else
    print_info "跳過自動清理"
fi

echo ""
print_info "診斷完成！"
echo ""
echo "如果仍有問題，請嘗試："
echo "  ./deploy.sh cleanup"
echo "  ./deploy.sh dev"
