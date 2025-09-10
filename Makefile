# MQTT Gear Server Makefile
# 提供便捷的項目管理命令

.PHONY: help setup start-broker start-b start-a stop-broker status clean monitor interactive batch

# 默認目標
help:
	@echo "MQTT Gear Server 管理命令:"
	@echo ""
	@echo "設置和初始化:"
	@echo "  make setup          - 初始化系統 (創建密碼文件等)"
	@echo "  make install-deps   - 安裝 Python 依賴"
	@echo ""
	@echo "啟動服務:"
	@echo "  make start-broker   - 啟動 MQTT Broker"
	@echo "  make start-b        - 啟動 B 端 (C# 執行端)"
	@echo "  make start-a        - 啟動 A 端 (Python 演算法端)"
	@echo "  make start-all      - 依序啟動所有服務"
	@echo ""
	@echo "停止服務:"
	@echo "  make stop-broker    - 停止 MQTT Broker"
	@echo "  make stop-all       - 停止所有服務"
	@echo ""
	@echo "監控和調試:"
	@echo "  make monitor        - 啟動系統監控器"
	@echo "  make status         - 顯示服務狀態"
	@echo "  make logs           - 顯示 Broker 日誌"
	@echo ""
	@echo "客戶端工具:"
	@echo "  make interactive    - A 端互動模式"
	@echo "  make batch          - A 端批次模式 (使用 sample_points.txt)"
	@echo "  make test-mqtt      - 測試 MQTT 連接"
	@echo ""
	@echo "清理和維護:"
	@echo "  make clean          - 清理日誌和臨時文件"
	@echo "  make reset          - 重設整個系統"

# 設置和初始化
setup:
	@echo "正在初始化 MQTT Gear Server..."
	chmod +x setup.sh
	./setup.sh

install-deps:
	@echo "安裝 Python 依賴..."
	cd client-python-A && pip install -r requirements.txt
	@echo "安裝 .NET 依賴..."
	cd client-csharp-B && dotnet restore

# 啟動服務
start-broker:
	@echo "啟動 MQTT Broker..."
	cd broker && docker compose up -d
	@echo "等待 Broker 啟動..."
	sleep 3
	@echo "Broker 狀態:"
	cd broker && docker compose ps

start-b:
	@echo "啟動 B 端 (C# 執行端)..."
	cd client-csharp-B && dotnet run

start-a:
	@echo "啟動 A 端 (Python 演算法端)..."
	cd client-python-A && python a_client.py

start-all: start-broker
	@echo "等待 5 秒讓 Broker 完全啟動..."
	sleep 5
	@echo "請在新終端中執行以下命令:"
	@echo "  make start-b  (啟動 B 端)"
	@echo "  make start-a  (啟動 A 端)"

# 停止服務
stop-broker:
	@echo "停止 MQTT Broker..."
	cd broker && docker compose down

stop-all: stop-broker
	@echo "所有服務已停止"

# 監控和調試
monitor:
	@echo "啟動系統監控器..."
	cd client-python-A && python monitor.py

status:
	@echo "=== MQTT Broker 狀態 ==="
	cd broker && docker compose ps
	@echo ""
	@echo "=== Docker 容器狀態 ==="
	docker ps --filter "name=mosquitto"

logs:
	@echo "顯示 MQTT Broker 日誌 (按 Ctrl+C 退出):"
	cd broker && docker compose logs -f

# 客戶端工具
interactive:
	@echo "啟動 A 端互動模式..."
	cd client-python-A && python a_tool.py --interactive

batch:
	@echo "啟動 A 端批次模式..."
	cd client-python-A && python a_tool.py --batch sample_points.txt

test-mqtt:
	@echo "測試 MQTT 連接..."
	@echo "發送測試消息..."
	mosquitto_pub -h 127.0.0.1 -p 1883 -u A_user -P A_password -t "test/connection" -m "Hello MQTT"
	@echo "監聽測試消息 (5秒):"
	timeout 5 mosquitto_sub -h 127.0.0.1 -p 1883 -u A_user -P A_password -t "test/connection" -v || true

# 清理和維護
clean:
	@echo "清理日誌和臨時文件..."
	rm -rf broker/data/* broker/log/*
	rm -f client-python-A/batch_results_*.json
	rm -f client-python-A/*.log
	@echo "清理完成"

reset: stop-all clean
	@echo "重設系統..."
	rm -f broker/passwd
	cd broker && docker compose down -v
	@echo "系統已重設，請重新執行 'make setup'"

# 開發工具
generate-points:
	@echo "生成範例點位文件..."
	cd client-python-A && python a_tool.py --generate sample_points_new.txt

check-deps:
	@echo "檢查依賴..."
	@command -v docker >/dev/null 2>&1 || { echo "錯誤: 需要安裝 Docker"; exit 1; }
	@command -v mosquitto_pub >/dev/null 2>&1 || { echo "錯誤: 需要安裝 mosquitto-clients"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "錯誤: 需要安裝 Python 3"; exit 1; }
	@command -v dotnet >/dev/null 2>&1 || { echo "錯誤: 需要安裝 .NET"; exit 1; }
	@echo "✓ 所有依賴已安裝"
