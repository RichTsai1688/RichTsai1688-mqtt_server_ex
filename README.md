# MQTT Gear Server

一個基於 MQTT 的齒輪振動分析系統，實現演算法端（A）與執行端（B）之間的即時通信和數據交換。

## 專案結構

```
mqtt_gear_server/
├─ broker/                     # MQTT Broker (Mosquitto)
│  ├─ docker-compose.yml       # Docker Compose 配置
│  ├─ mosquitto.conf          # Mosquitto 配置
│  ├─ acl                     # 訪問控制列表
│  ├─ passwd                  # 用戶密碼文件 (需生成)
│  └─ certs/                  # TLS 憑證目錄
├─ client-python-A/           # A端 - Python 演算法客戶端
│  ├─ a_client.py             # 主程序
│  └─ requirements.txt        # Python 依賴
├─ client-csharp-B/           # B端 - C# 執行客戶端
│  ├─ Program.cs              # 主程序
│  └─ BClient.csproj          # 專案文件
└─ setup.sh                   # 初始化腳本
```

## 系統特性

### 🔄 Request/Response 模式
- A 端發送 `cmd/point` 指令後**阻塞等待** B 端的 `telemetry/result`
- 使用 `req_id` (UUID) 關聯請求與回應，確保消息對應
- 支持**逾時重試**和**幂等性**保證

### 📡 MQTT Topic 設計
- `v1/{id}/ctrl/start` - B→A，觸發流程開始
- `v1/{id}/ctrl/end` - A→B，流程結束信號  
- `v1/{id}/cmd/point` - A→B，點位移動指令
- `v1/{id}/telemetry/result` - B→A，振動分析結果
- `v1/{id}/config/setting` - 雙向，系統配置 (retained)
- `v1/{id}/status` - 設備狀態 (retained)

### 🔒 安全特性
- **ACL 權限控制**：A、B 用戶只能訪問授權的 Topic
- **TLS 支持**：可配置加密傳輸（8883 端口）
- **用戶驗證**：基於用戶名/密碼的身份驗證

### 🛡️ 可靠性保證
- **QoS 1/2**：確保重要消息送達
- **Retained Messages**：狀態和配置消息持久化
- **遺囑消息**：設備離線自動通知
- **錯誤處理**：完善的異常處理和重試機制

## 🚀 快速開始

### 方法 1: 🐳 Docker 一鍵部署 (推薦)

```bash
# 進入 broker 目錄
cd broker

# 一鍵部署開發環境
./deploy.sh dev

# 或部署生產環境 (包含監控)
./deploy.sh prod

# 檢查部署狀態
./monitor.sh
```

### 方法 2: 📋 手動部署

#### 1. 環境準備

**安裝依賴：**
```bash
# macOS
brew install mosquitto docker

# Ubuntu  
sudo apt-get install mosquitto-clients docker.io docker-compose

# Python 依賴
cd client-python-A
pip install -r requirements.txt

# .NET 依賴 (需要 .NET 8.0)
cd client-csharp-B
dotnet restore
```

#### 2. 初始化系統

```bash
# 執行初始化腳本
chmod +x setup.sh
./setup.sh
```

此腳本會：
- 創建 MQTT 用戶密碼文件
- 設置必要的目錄權限  
- 提供後續啟動指引

#### 3. 啟動系統

**步驟 1: 啟動 MQTT Broker**
```bash
cd broker
docker compose up -d

# 查看日誌
docker compose logs -f

# 或使用監控腳本
./monitor.sh watch
```

**步驟 2: 啟動 B 端（執行端）**
```bash
cd client-csharp-B
dotnet run
```

**步驟 3: 啟動 A 端（演算法端）**  
```bash
cd client-python-A
python a_client.py
```

### 4. 系統運行流程

1. **B 端連接** → 發送上線狀態和初始配置
2. **A 端連接** → 訂閱相關 Topic
3. **B 端觸發** → 發送 `start` 信號給 A 端
4. **A 端執行** → 依序發送點位指令並等待結果
5. **B 端響應** → 執行移動和分析，回傳結果
6. **流程結束** → A 端發送 `end` 信號

## 配置說明

### MQTT Broker 配置

**基本連接：**
- 地址：`127.0.0.1:1883` (非加密)
- TLS：`127.0.0.1:8883` (需配置憑證)
- WebSocket：`127.0.0.1:9001` (可選)

**用戶權限：**
- `A_user`：演算法端，可發送指令、接收結果
- `B_user`：執行端，可接收指令、發送結果

### 客戶端配置

**A 端 (Python)：**
```python
BROKER_HOST = "127.0.0.1"
PORT = 1883
USER = "A_user" 
PASS = "A_password"  # setup.sh 中設置
```

**B 端 (C#)：**
```csharp
static string Host = "127.0.0.1";
static int Port = 1883;
static string User = "B_user";
static string Pass = "B_password";  // setup.sh 中設置
```

## 開發指南

### 消息格式範例

**點位指令 (A→B)：**
```json
{
  "type": "move_point",
  "point": {"x": 10.5, "y": -7.2},
  "ts": 1694678400,
  "sender": "A",
  "req_id": "uuid-string"
}
```

**分析結果 (B→A)：**
```json
{
  "type": "result_feature_set", 
  "features": ["Time_rms_y", "Time_skewness_y", "..."],
  "values": [1.23, -0.05, "..."],
  "point": {"x": 10.5, "y": -7.2},
  "req_id": "uuid-string",
  "ts": 1694678401,
  "sender": "B"
}
```

### 擴展功能

**添加新的 Topic：**
1. 在 `acl` 文件中添加權限規則
2. 在客戶端代碼中添加訂閱和處理邏輯
3. 重啟 MQTT Broker 使 ACL 生效

**TLS 配置：**
1. 將憑證文件放入 `broker/certs/` 目錄
2. 修改客戶端連接端口為 8883
3. 在客戶端代碼中添加 TLS 設置

## 故障排除

**常見問題：**

1. **連接被拒絕：** 檢查用戶名密碼是否正確
2. **權限錯誤：** 確認 `acl` 文件配置和用戶權限
3. **消息丟失：** 檢查 QoS 設置和網路狀況
4. **Docker 啟動失敗：** 確認端口未被占用

**調試命令：**
```bash
# 查看 Broker 日誌
docker compose -f broker/docker-compose.yml logs -f

# 測試 MQTT 連接
mosquitto_pub -h 127.0.0.1 -p 1883 -u A_user -P A_password -t test -m "hello"

# 監聽所有消息  
mosquitto_sub -h 127.0.0.1 -p 1883 -u A_user -P A_password -t '#' -v
```

## 效能調優

- **批量處理**：可修改 A 端支持並行發送多個點位
- **消息壓縮**：對大型結果數據可考慮壓縮
- **快取機制**：B 端已實現 `req_id` 結果快取
- **QoS 優化**：根據業務需求調整 QoS 級別

## 授權

此專案基於 MIT 授權條款發布。
