#!/bin/bash

# MQTT Gear Server 設置腳本
# 此腳本會創建 MQTT 用戶密碼文件

echo "=== MQTT Gear Server 初始化 ==="

# 進入 broker 目錄
cd "$(dirname "$0")/broker"

# 檢查是否已安裝 mosquitto
if ! command -v mosquitto_passwd &> /dev/null; then
    echo "錯誤: 未找到 mosquitto_passwd 命令"
    echo "請先安裝 Mosquitto:"
    echo "  macOS: brew install mosquitto"
    echo "  Ubuntu: sudo apt-get install mosquitto-clients"
    exit 1
fi

# 創建密碼文件
echo "正在創建 MQTT 用戶..."

# 刪除舊的密碼文件（如果存在）
rm -f passwd

# 創建 A_user
echo "設置 A_user 密碼..."
mosquitto_passwd -c passwd A_user

# 添加 B_user  
echo "設置 B_user 密碼..."
mosquitto_passwd passwd B_user

echo "密碼文件創建完成: $(pwd)/passwd"

# 創建必要的目錄
echo "創建數據目錄..."
mkdir -p data log

# 設置權限
chmod 644 passwd
chmod 644 acl
chmod 644 mosquitto.conf

echo "=== 初始化完成 ==="
echo ""
echo "下一步:"
echo "1. 啟動 MQTT Broker: cd broker && docker compose up -d"
echo "2. 啟動 B 客戶端: cd client-csharp-B && dotnet run"
echo "3. 啟動 A 客戶端: cd client-python-A && python a_client.py"
echo ""
echo "查看 broker 日誌: docker compose -f broker/docker-compose.yml logs -f"
