#!/bin/bash

# MQTT Gear Server 快速示例腳本

set -e

echo "🐳 MQTT Gear Server 快速示例"
echo "==============================================="
echo ""

# 檢查當前目錄
if [[ ! -f "broker/config.sh" ]]; then
    echo "❌ 請在專案根目錄執行此腳本"
    exit 1
fi

echo "📋 步驟 1: 系統配置"
echo "正在檢查配置..."

cd broker

# 如果沒有 .env 文件，使用默認配置
if [[ ! -f ".env" ]]; then
    echo "  複製預設配置..."
    cp .env.template .env
    echo "  ✅ 已使用預設配置 (IP: 140.134.60.218)"
else
    echo "  ✅ 找到現有配置文件"
fi

# 顯示當前配置
echo ""
echo "當前配置:"
grep "MQTT_BROKER_IP\|MQTT_PORT" .env | head -2

echo ""
echo "📋 步驟 2: 部署 MQTT Broker"
echo "正在啟動 Docker 容器..."

# 部署開發環境
./deploy.sh dev

if [[ $? -eq 0 ]]; then
    echo "  ✅ MQTT Broker 啟動成功"
else
    echo "  ❌ MQTT Broker 啟動失敗"
    exit 1
fi

echo ""
echo "📋 步驟 3: 測試系統連接"
sleep 3  # 等待服務啟動

# 獲取配置
BROKER_IP=$(grep "^MQTT_BROKER_IP=" .env | cut -d'=' -f2)
MQTT_PORT=$(grep "^MQTT_PORT=" .env | cut -d'=' -f2)

echo "正在測試連接到 $BROKER_IP:$MQTT_PORT..."

# 測試連接
if command -v mosquitto_pub &> /dev/null; then
    if mosquitto_pub -h $BROKER_IP -p $MQTT_PORT -t test/demo -m "Hello MQTT Gear Server" -q 2>/dev/null; then
        echo "  ✅ 連接測試成功"
    else
        echo "  ⚠️  連接測試失敗（可能需要用戶認證）"
    fi
else
    echo "  ⚠️  mosquitto_pub 未安裝，跳過連接測試"
fi

echo ""
echo "📋 步驟 4: 準備客戶端"

# 檢查 Python 環境
cd ../client-python-A
echo "檢查 Python 依賴..."
if [[ -f "requirements.txt" ]]; then
    if pip list | grep -q paho-mqtt; then
        echo "  ✅ Python MQTT 依賴已安裝"
    else
        echo "  📦 正在安裝 Python 依賴..."
        pip install -r requirements.txt
    fi
fi

# 檢查 .NET 環境
cd ../client-csharp-B
echo "檢查 .NET 環境..."
if command -v dotnet &> /dev/null; then
    if dotnet --version &> /dev/null; then
        echo "  ✅ .NET 環境可用"
        echo "  📦 還原 NuGet 包..."
        dotnet restore > /dev/null 2>&1
    fi
else
    echo "  ⚠️  .NET 未安裝，請安裝 .NET 8.0 SDK"
fi

cd ..

echo ""
echo "🎉 系統準備完成！"
echo "==============================================="
echo ""
echo "📱 監控面板:"
echo "  系統狀態: ./broker/monitor.sh"
echo "  MQTT 日誌: ./broker/monitor.sh logs"
echo ""
echo "🚀 啟動客戶端:"
echo ""
echo "  1️⃣  啟動 B 端 (執行端):"
echo "     cd client-csharp-B && dotnet run"
echo ""
echo "  2️⃣  啟動 A 端 (演算法端):"
echo "     cd client-python-A && python a_client.py"
echo ""
echo "⚙️  調整配置:"
echo "     ./broker/config.sh"
echo ""
echo "📖 詳細文檔:"
echo "     cat CONFIG.md"
echo ""
echo "🐳 Docker 狀態:"

# 顯示 Docker 狀態
cd broker
docker compose ps

echo ""
echo "✨ 準備就緒！按上述步驟啟動客戶端即可開始使用。"
