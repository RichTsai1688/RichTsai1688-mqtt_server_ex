#!/bin/bash

# 快速啟動腳本
# 適用於 macOS/Linux 系統

set -e  # 遇到錯誤立即退出

echo "=== MQTT Gear Server 快速啟動 ==="

# 檢查依賴
echo "檢查系統依賴..."

if ! command -v docker &> /dev/null; then
    echo "❌ 錯誤: 需要安裝 Docker"
    echo "   macOS: brew install docker"
    echo "   Ubuntu: sudo apt-get install docker.io"
    exit 1
fi

if ! command -v mosquitto_pub &> /dev/null; then
    echo "❌ 錯誤: 需要安裝 Mosquitto 客戶端工具"
    echo "   macOS: brew install mosquitto"
    echo "   Ubuntu: sudo apt-get install mosquitto-clients"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "❌ 錯誤: 需要安裝 Python 3"
    exit 1
fi

if ! command -v dotnet &> /dev/null; then
    echo "❌ 錯誤: 需要安裝 .NET SDK"
    echo "   請從 https://dotnet.microsoft.com/ 下載安裝"
    exit 1
fi

echo "✅ 系統依賴檢查通過"

# 初始化系統 (如果需要)
if [ ! -f "broker/passwd" ]; then
    echo "初始化系統..."
    ./setup.sh
fi

# 安裝 Python 依賴
echo "安裝 Python 依賴..."
cd client-python-A
if [ ! -f "venv/bin/activate" ]; then
    echo "創建 Python 虛擬環境..."
    python3 -m venv venv
fi
source venv/bin/activate
pip install -q -r requirements.txt
cd ..

# 安裝 .NET 依賴
echo "安裝 .NET 依賴..."
cd client-csharp-B
dotnet restore --verbosity quiet
cd ..

# 啟動 MQTT Broker
echo "啟動 MQTT Broker..."
cd broker
docker compose up -d
echo "等待 Broker 啟動..."
sleep 5

# 檢查 Broker 狀態
if ! docker compose ps | grep -q "Up"; then
    echo "❌ MQTT Broker 啟動失敗"
    docker compose logs
    exit 1
fi

echo "✅ MQTT Broker 已啟動"
cd ..

echo ""
echo "🎉 系統啟動完成！"
echo ""
echo "接下來請打開新的終端窗口並執行："
echo ""
echo "1️⃣  啟動 B 端 (執行端)："
echo "   cd client-csharp-B && dotnet run"
echo ""
echo "2️⃣  啟動 A 端 (演算法端)："
echo "   cd client-python-A && source venv/bin/activate && python a_client.py"
echo ""
echo "或者使用工具模式："
echo "   cd client-python-A && source venv/bin/activate && python a_tool.py --interactive"
echo ""
echo "🔍 監控系統："
echo "   cd client-python-A && source venv/bin/activate && python monitor.py"
echo ""
echo "🛑 停止系統："
echo "   make stop-broker 或 cd broker && docker compose down"
echo ""

# 測試連接
echo "測試 MQTT 連接..."
if mosquitto_pub -h 127.0.0.1 -p 1883 -u A_user -P A_password -t "test/startup" -m "System Ready" 2>/dev/null; then
    echo "✅ MQTT 連接測試成功"
else
    echo "⚠️  MQTT 連接測試失敗，請檢查密碼設置"
fi

echo ""
echo "系統已準備就緒! 🚀"
