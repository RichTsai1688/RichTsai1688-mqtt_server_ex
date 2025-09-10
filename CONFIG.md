# MQTT Gear Server 配置指南

## 系統配置總覽

MQTT Gear Server 採用環境變數配置系統，所有關鍵參數都可透過 `.env` 文件進行統一管理。

## 配置工具

### 互動式配置工具

```bash
cd broker
./config.sh
```

此工具提供：
- 🌐 IP 地址設置（localhost/遠端/自訂）
- 🔌 端口配置（標準/自訂）
- 👤 用戶管理
- 🔗 連接測試
- 📝 客戶端配置生成

### 手動配置

複製模板文件：
```bash
cp .env.template .env
```

## 主要配置項

### 網路配置

| 變數名 | 預設值 | 說明 |
|--------|--------|------|
| `MQTT_BROKER_IP` | 140.134.60.218 | MQTT Broker IP 地址 |
| `MQTT_PORT` | 4883 | MQTT 標準端口 |
| `MQTT_TLS_PORT` | 4884 | MQTT TLS 加密端口 |
| `MQTT_WS_PORT` | 9021 | WebSocket 端口 |

### 內部端口映射

| 變數名 | 預設值 | 說明 |
|--------|--------|------|
| `MQTT_INTERNAL_PORT` | 1883 | Docker 內部 MQTT 端口 |
| `MQTT_INTERNAL_TLS_PORT` | 8883 | Docker 內部 TLS 端口 |
| `MQTT_INTERNAL_WS_PORT` | 9001 | Docker 內部 WebSocket 端口 |

### 用戶配置

| 變數名 | 預設值 | 說明 |
|--------|--------|------|
| `MQTT_A_USER` | A_user | A 端（演算法端）用戶名 |
| `MQTT_B_USER` | B_user | B 端（執行端）用戶名 |
| `MQTT_MONITOR_USER` | monitor_user | 監控用戶名 |
| `MQTT_CLIENT_ID` | id1 | 客戶端識別碼 |

### 監控服務端口

| 變數名 | 預設值 | 說明 |
|--------|--------|------|
| `PROMETHEUS_PORT` | 9090 | Prometheus 監控端口 |
| `GRAFANA_PORT` | 3000 | Grafana 儀表板端口 |
| `MQTT_EXPORTER_PORT` | 9234 | MQTT 指標導出端口 |

## 部署環境設定

### 開發環境

```bash
# 使用 localhost 配置
MQTT_BROKER_IP=127.0.0.1
MQTT_PORT=4883
```

### 測試環境

```bash
# 使用您指定的測試伺服器
MQTT_BROKER_IP=140.134.60.218
MQTT_PORT=4883
```

### 生產環境

```bash
# 使用標準端口和生產 IP
MQTT_BROKER_IP=your-production-ip
MQTT_PORT=1883
MQTT_TLS_PORT=8883

# 啟用 TLS 和監控
# 在 docker-compose.prod.yml 中自動配置
```

## 安全配置

### TLS 加密

TLS 憑證位置：
```
broker/certs/
├── ca.crt          # CA 憑證
├── server.crt      # 伺服器憑證
└── server.key      # 伺服器私鑰
```

生成自簽憑證：
```bash
cd broker
./generate_certs.sh
```

### ACL 權限控制

權限配置文件：`broker/acl`

```
# A 用戶權限
user A_user
topic readwrite v1/id1/cmd/+
topic readwrite v1/id1/telemetry/+
topic read v1/id1/ctrl/+
topic write v1/id1/status

# B 用戶權限  
user B_user
topic readwrite v1/id1/ctrl/+
topic readwrite v1/id1/telemetry/+
topic read v1/id1/cmd/+
topic write v1/id1/status
```

### 用戶密碼

密碼在部署時自動生成：
```bash
./deploy.sh dev    # 開發環境
./deploy.sh prod   # 生產環境
```

## 客戶端配置

### Python 客戶端配置

配置透過環境變數載入：
```python
import os
BROKER_HOST = os.getenv("MQTT_BROKER_IP", "140.134.60.218")
BROKER_PORT = int(os.getenv("MQTT_PORT", "4883"))
```

運行前設置環境變數：
```bash
source config.env  # 由 config.sh 生成
python a_client.py
```

### C# 客戶端配置

使用 `appsettings.json` 配置：
```json
{
  "MqttSettings": {
    "BrokerIP": "140.134.60.218",
    "Port": 4883,
    "ClientId": "id1",
    "BUser": "B_user"
  }
}
```

或使用環境變數：
```csharp
string brokerIP = Environment.GetEnvironmentVariable("MQTT_BROKER_IP") ?? "140.134.60.218";
```

## 監控配置

### Prometheus 配置

配置文件：`broker/monitoring/prometheus.yml`

監控指標：
- MQTT 連接數
- 消息吞吐量
- 主題統計
- 系統資源使用

### Grafana 儀表板

存取：http://your-ip:3000
- 用戶名：admin
- 密碼：admin

預設儀表板：
- MQTT Broker 概覽
- 客戶端連接監控
- 消息流量分析

## 疑難排解

### 連接問題

1. **檢查 IP 和端口**：
   ```bash
   ./config.sh
   # 選擇 "5) 測試連接"
   ```

2. **檢查防火牆**：
   ```bash
   # 開放 MQTT 端口
   sudo ufw allow 4883
   sudo ufw allow 4884
   ```

3. **檢查 Docker 狀態**：
   ```bash
   ./monitor.sh
   ```

### 權限問題

1. **重新生成密碼文件**：
   ```bash
   ./deploy.sh dev
   ```

2. **檢查 ACL 配置**：
   ```bash
   cat acl
   ```

### 監控問題

1. **檢查監控服務**：
   ```bash
   docker compose -f docker-compose.prod.yml logs grafana
   ```

2. **重啟監控堆疊**：
   ```bash
   ./deploy.sh prod
   ```

## 配置檢查清單

部署前請確認：

- [ ] `.env` 文件已配置正確的 IP 地址
- [ ] 端口沒有衝突
- [ ] 防火牆規則已設置
- [ ] 客戶端配置文件已生成
- [ ] TLS 憑證已準備（如需要）
- [ ] 用戶權限已配置

使用配置工具可一鍵完成大部分檢查：
```bash
./config.sh
```
