#!/bin/bash

# 簡單的 MQTT Broker 啟動腳本
echo "正在啟動簡單的 MQTT Broker..."

cd /Users/rich/Documents/code/mqtt_gear_server/broker

# 停止現有的容器（如果有）
echo "停止現有容器..."
docker-compose -f docker-compose-simple.yml down 2>/dev/null || true

# 創建必要的目錄
mkdir -p data log

# 啟動新的簡單配置
echo "啟動 MQTT Broker (簡單版本)..."
docker-compose -f docker-compose-simple.yml up -d

# 等待服務啟動
echo "等待服務啟動..."
sleep 3

# 檢查狀態
echo "檢查服務狀態..."
docker-compose -f docker-compose-simple.yml ps

echo ""
echo "✅ MQTT Broker 已啟動！"
echo "📝 配置詳情："
echo "   - 地址: localhost:1883"
echo "   - 認證: 匿名連接"
echo "   - TLS: 未啟用"
echo ""
echo "🧪 測試連接："
echo "   mosquitto_pub -h localhost -p 1883 -t test -m 'Hello World'"
echo "   mosquitto_sub -h localhost -p 1883 -t test"
