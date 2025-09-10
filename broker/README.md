# 📁 MQTT Broker 目錄說明

這個目錄包含了完整的 MQTT Broker Docker 部署方案，支持開發和生產環境。

## 🗂️ 文件結構

```
broker/
├── 📋 DOCKER_DEPLOY.md      # Docker 詳細部署指南
├── 🚀 deploy.sh             # 自動部署腳本 (一鍵部署)
├── 📊 monitor.sh            # 狀態監控腳本
│
├── 🐳 docker-compose.yml    # 開發環境配置
├── 🏭 docker-compose.prod.yml  # 生產環境配置 (含監控)
│
├── ⚙️  mosquitto.conf       # Mosquitto 主配置
├── 🔒 acl                   # 權限控制列表
├── 👤 passwd.template       # 密碼文件模板
│
├── 🔐 certs/                # TLS 憑證目錄
│   └── README.md           # 憑證生成說明
│
├── 📁 data/                 # 持久化數據 (自動生成)
├── 📝 log/                  # 日誌文件 (自動生成)
└── 💾 backup/               # 備份文件 (自動生成)
```

## 🎯 快速開始

### 🚀 一鍵部署 (推薦)

```bash
# 開發環境 (基礎功能)
./deploy.sh dev

# 生產環境 (含監控)
./deploy.sh prod

# 檢查狀態
./monitor.sh
```

### 📊 監控面板

```bash
# 實時監控
./monitor.sh watch

# 檢查特定項目
./monitor.sh services     # 服務狀態
./monitor.sh resources    # 資源使用
./monitor.sh ports        # 端口狀態
./monitor.sh connection   # MQTT 連接測試
./monitor.sh config       # 配置檢查
```

### 🛠️ 手動管理

```bash
# 啟動服務
docker-compose up -d                           # 開發環境
docker-compose -f docker-compose.prod.yml up -d   # 生產環境

# 查看狀態
docker-compose ps
./deploy.sh status

# 查看日誌
docker-compose logs -f mosquitto
tail -f log/mosquitto.log

# 停止服務
docker-compose down
./deploy.sh cleanup
```

## 🔧 配置說明

### 開發環境 (docker-compose.yml)
- ✅ 基礎 MQTT Broker
- ✅ TLS 加密支持
- ✅ 用戶認證 + ACL 權限控制
- ✅ 數據持久化
- ✅ 健康檢查
- ✅ 資源限制

### 生產環境 (docker-compose.prod.yml)
開發環境的所有功能 +
- 🚀 Prometheus 監控系統
- 📊 Grafana 視覺化面板
- 📈 MQTT 指標導出器
- 🗄️ Redis 快取服務
- ⚖️ Nginx 負載均衡
- 💾 自動備份服務
- 🔍 完整的日誌管理

## 🌐 服務端口

### 開發環境
- `1883` - MQTT (非加密)
- `8883` - MQTT TLS (加密)
- `9001` - WebSocket

### 生產環境 (額外)
- `3000` - Grafana 監控面板
- `9090` - Prometheus 監控系統
- `9234` - MQTT 指標接口
- `6379` - Redis 快取服務

## 🔒 安全特性

- **TLS 加密**: 自動生成自簽名憑證
- **用戶認證**: 基於用戶名/密碼
- **ACL 權限控制**: 細粒度主題權限
- **容器隔離**: Docker 網絡隔離
- **資源限制**: CPU/內存使用限制

## 📈 監控功能

### 自動健康檢查
- MQTT Broker 連通性
- 服務響應時間
- 資源使用情況
- 端口監聽狀態

### Grafana 監控面板
- 連接數統計
- 消息吞吐量
- 錯誤率監控
- 系統資源使用

### 告警功能
- 服務異常自動告警
- 資源使用超限告警
- 連接數異常告警

## 💾 備份恢復

### 自動備份
- 每日自動備份數據
- 保留最近 7 天備份
- 包含配置和持久化數據

### 手動備份
```bash
# 創建備份
tar -czf mqtt_backup_$(date +%Y%m%d).tar.gz data log passwd acl mosquitto.conf

# 恢復備份
docker-compose down
tar -xzf mqtt_backup_YYYYMMDD.tar.gz
docker-compose up -d
```

## 🐛 故障排除

### 常見問題
1. **容器無法啟動**: 檢查端口衝突、權限設置
2. **認證失敗**: 驗證密碼文件、ACL 配置
3. **TLS 連接失敗**: 檢查憑證有效性、時間同步
4. **性能問題**: 調整資源限制、優化配置

### 調試工具
```bash
./monitor.sh config       # 配置檢查
./monitor.sh connection   # 連接測試
docker logs mosquitto     # 容器日誌
./deploy.sh status        # 整體狀態
```

## 📚 相關文檔

- 📖 [Docker 詳細部署指南](DOCKER_DEPLOY.md)
- 🔐 [TLS 憑證配置](certs/README.md)
- 📊 [主專案說明](../README.md)
- 🎯 [專案總覽](../PROJECT_OVERVIEW.md)

---

**提示**: 建議先使用開發環境測試功能，確認無誤後再部署到生產環境。
