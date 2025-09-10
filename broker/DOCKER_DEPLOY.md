# 🐳 Mosquitto MQTT Broker Docker 部署指南

這份指南將詳細說明如何使用 Docker Container 架設 Mosquitto MQTT Broker，包含 TLS 加密和 ACL 權限控制。

## 📋 目錄結構

```
broker/
├── 🐳 docker-compose.yml     # Docker Compose 主配置
├── ⚙️ mosquitto.conf         # Mosquitto 配置文件
├── 🔒 acl                    # 權限控制列表
├── 👤 passwd                 # 用戶密碼文件 (需生成)
├── 📁 data/                  # 持久化數據目錄
├── 📝 log/                   # 日誌文件目錄
├── 🔐 certs/                 # TLS 憑證目錄
│   ├── ca.crt               # CA 根憑證
│   ├── server.crt           # 服務器憑證
│   └── server.key           # 服務器私鑰
└── 📖 DOCKER_DEPLOY.md      # 本文件
```

## 🚀 快速部署

### 1. 前置準備

```bash
# 進入 broker 目錄
cd broker

# 創建必要的目錄
mkdir -p data log certs

# 設置目錄權限 (重要!)
sudo chown -R 1883:1883 data log
chmod 755 data log
chmod 644 mosquitto.conf acl
```

### 2. 生成用戶密碼

```bash
# 方法 1: 使用本地 mosquitto_passwd (推薦)
# macOS: brew install mosquitto
# Ubuntu: sudo apt-get install mosquitto-clients

mosquitto_passwd -c passwd A_user     # 創建 A_user
mosquitto_passwd passwd B_user        # 添加 B_user

# 方法 2: 使用 Docker 臨時容器
docker run -it --rm -v $(pwd):/data eclipse-mosquitto:2 mosquitto_passwd -c /data/passwd A_user
docker run -it --rm -v $(pwd):/data eclipse-mosquitto:2 mosquitto_passwd /data/passwd B_user
```

### 3. 啟動 MQTT Broker

```bash
# 啟動容器 (背景運行)
docker compose up -d

# 查看容器狀態
docker compose ps

# 查看啟動日誌
docker compose logs -f
```

## 🔧 Docker Compose 配置詳解

### 基本配置

```yaml
version: '3.8'

services:
  mosquitto:
    image: eclipse-mosquitto:2           # 使用官方 Mosquitto v2
    container_name: mosquitto           # 容器名稱
    restart: unless-stopped             # 自動重啟策略
```

### 端口映射

```yaml
ports:
  - "1883:1883"    # MQTT 標準端口 (非加密)
  - "8883:8883"    # MQTT over TLS 端口 (加密)
  - "9001:9001"    # WebSocket 端口 (可選)
```

### 數據卷掛載

```yaml
volumes:
  # 配置文件 (只讀)
  - ./mosquitto.conf:/mosquitto/config/mosquitto.conf:ro
  - ./acl:/mosquitto/config/acl:ro
  - ./passwd:/mosquitto/config/passwd:ro
  - ./certs:/mosquitto/certs:ro
  
  # 數據目錄 (讀寫)
  - ./data:/mosquitto/data              # 持久化數據
  - ./log:/mosquitto/log                # 日誌文件
```

### 網絡配置

```yaml
networks:
  - mqtt-network

networks:
  mqtt-network:
    driver: bridge                      # 橋接網絡模式
```

## 🔒 TLS 加密配置

### 1. 生成自簽名憑證 (開發環境)

```bash
cd certs

# 生成 CA 私鑰
openssl genrsa -out ca.key 2048

# 生成 CA 根憑證
openssl req -new -x509 -key ca.key -out ca.crt -days 365 \
  -subj "/C=TW/ST=Taiwan/L=Taipei/O=MQTT-Gear/CN=MQTT-CA"

# 生成服務器私鑰
openssl genrsa -out server.key 2048

# 生成服務器憑證簽署請求
openssl req -new -key server.key -out server.csr \
  -subj "/C=TW/ST=Taiwan/L=Taipei/O=MQTT-Gear/CN=localhost"

# 用 CA 簽署服務器憑證
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt -days 365

# 設置文件權限
chmod 600 server.key ca.key
chmod 644 server.crt ca.crt

# 清理臨時文件
rm server.csr ca.key ca.srl
```

### 2. TLS 配置驗證

```bash
# 測試 TLS 連接
mosquitto_pub -h localhost -p 8883 --cafile certs/ca.crt \
  -u A_user -P [密碼] -t test/tls -m "TLS Test"

# 監聽 TLS 消息
mosquitto_sub -h localhost -p 8883 --cafile certs/ca.crt \
  -u A_user -P [密碼] -t test/tls
```

## 🛡️ 安全配置

### ACL 權限控制

```bash
# 查看 ACL 配置
cat acl

# A_user 權限:
# - 讀取: v1/id1/ctrl/#, v1/id1/telemetry/result, v1/id1/config/setting
# - 寫入: v1/id1/ctrl/end, v1/id1/cmd/point, v1/id1/status

# B_user 權限:
# - 讀取: v1/id1/cmd/point, v1/id1/config/setting
# - 寫入: v1/id1/ctrl/start, v1/id1/telemetry/result, v1/id1/status
```

### 用戶管理

```bash
# 添加新用戶
docker exec mosquitto mosquitto_passwd /mosquitto/config/passwd new_user

# 刪除用戶
docker exec mosquitto mosquitto_passwd -D /mosquitto/config/passwd old_user

# 重新加載配置 (不重啟容器)
docker exec mosquitto kill -HUP 1
```

## 📊 監控和管理

### 容器狀態檢查

```bash
# 查看容器狀態
docker compose ps

# 查看資源使用情況
docker stats mosquitto

# 查看容器詳細信息
docker inspect mosquitto
```

### 日誌管理

```bash
# 查看 Docker 日誌
docker compose logs mosquitto

# 查看 Mosquitto 日誌文件
tail -f log/mosquitto.log

# 限制日誌大小 (在 docker-compose.yml 中添加)
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

### 性能調優

```bash
# 在 docker-compose.yml 中限制資源
deploy:
  resources:
    limits:
      cpus: '0.5'
      memory: 512M
    reservations:
      memory: 256M

# 調整 Mosquitto 配置
# mosquitto.conf 中添加:
# max_connections 1000
# max_queued_messages 1000
# message_size_limit 0
```

## 🔄 備份和恢復

### 數據備份

```bash
# 創建數據備份
tar -czf mqtt_backup_$(date +%Y%m%d_%H%M%S).tar.gz \
  data/ log/ passwd acl mosquitto.conf certs/

# 定期備份腳本 (加入 crontab)
0 2 * * * /path/to/backup_script.sh
```

### 數據恢復

```bash
# 停止服務
docker compose down

# 恢復數據
tar -xzf mqtt_backup_YYYYMMDD_HHMMSS.tar.gz

# 重新啟動
docker compose up -d
```

## 🐛 故障排除

### 常見問題

1. **容器無法啟動**
   ```bash
   # 檢查配置文件語法
   docker run --rm -v $(pwd)/mosquitto.conf:/mosquitto/config/mosquitto.conf \
     eclipse-mosquitto:2 mosquitto -c /mosquitto/config/mosquitto.conf -v
   
   # 檢查端口衝突
   netstat -tulpn | grep -E "1883|8883|9001"
   ```

2. **權限錯誤**
   ```bash
   # 修復數據目錄權限
   sudo chown -R 1883:1883 data log
   chmod 755 data log
   ```

3. **TLS 連接失敗**
   ```bash
   # 驗證憑證
   openssl x509 -in certs/server.crt -text -noout
   
   # 測試 TLS 握手
   openssl s_client -connect localhost:8883 -servername localhost
   ```

### 調試模式

```bash
# 以調試模式啟動 (暫時)
docker run -it --rm -p 1883:1883 -p 8883:8883 \
  -v $(pwd)/mosquitto.conf:/mosquitto/config/mosquitto.conf \
  -v $(pwd)/acl:/mosquitto/config/acl \
  -v $(pwd)/passwd:/mosquitto/config/passwd \
  -v $(pwd)/certs:/mosquitto/certs \
  eclipse-mosquitto:2 mosquitto -c /mosquitto/config/mosquitto.conf -v
```

## 📈 進階配置

### 集群部署

```yaml
# docker-compose.cluster.yml
version: '3.8'

services:
  mosquitto-1:
    image: eclipse-mosquitto:2
    # ... 配置 ...
    
  mosquitto-2:
    image: eclipse-mosquitto:2
    # ... 配置 ...
    
  haproxy:
    image: haproxy:2.4
    # 負載均衡配置
```

### 監控集成

```yaml
# 添加 Prometheus 監控
  mqtt-exporter:
    image: sapcc/mosquitto-exporter
    environment:
      - MQTT_BROKER_URL=tcp://mosquitto:1883
      - MQTT_USER=monitor_user
      - MQTT_PASS=monitor_password
```

## 📚 參考資源

- [Eclipse Mosquitto 官方文檔](https://mosquitto.org/documentation/)
- [Docker Hub - Eclipse Mosquitto](https://hub.docker.com/_/eclipse-mosquitto)
- [MQTT 協議規範](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html)
- [OpenSSL 憑證管理](https://www.openssl.org/docs/man1.1.1/man1/)

---

## 🚀 一鍵部署腳本

創建 `deploy.sh` 快速部署腳本:

```bash
#!/bin/bash
set -e

echo "🐳 部署 Mosquitto MQTT Broker..."

# 創建目錄
mkdir -p data log certs

# 生成密碼文件
if [ ! -f passwd ]; then
    echo "生成用戶密碼..."
    docker run -it --rm -v $(pwd):/data eclipse-mosquitto:2 \
        mosquitto_passwd -c /data/passwd A_user
    docker run -it --rm -v $(pwd):/data eclipse-mosquitto:2 \
        mosquitto_passwd /data/passwd B_user
fi

# 設置權限
sudo chown -R 1883:1883 data log 2>/dev/null || true
chmod 755 data log
chmod 644 mosquitto.conf acl

# 啟動服務
docker compose up -d

# 等待啟動
sleep 5

# 檢查狀態
docker compose ps

echo "✅ MQTT Broker 部署完成!"
echo "📡 MQTT 端口: 1883"
echo "🔒 MQTTS 端口: 8883"
echo "🌐 WebSocket 端口: 9001"
```

現在您有了完整的 Docker 部署方案！🎉
