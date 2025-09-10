# TLS 憑證目錄

這個目錄用於存放 TLS 憑證文件，啟用 MQTT over TLS (8883 端口)。

## 需要的文件

- `ca.crt` - 證書頒發機構 (CA) 根憑證
- `server.crt` - 服務器憑證  
- `server.key` - 服務器私鑰

## 生成自簽名憑證 (開發用)

```bash
# 生成 CA 私鑰
openssl genrsa -out ca.key 2048

# 生成 CA 憑證
openssl req -new -x509 -key ca.key -out ca.crt -days 365 \
  -subj "/C=TW/ST=Taiwan/L=Taipei/O=MQTT-Gear/CN=MQTT-CA"

# 生成服務器私鑰  
openssl genrsa -out server.key 2048

# 生成服務器憑證請求
openssl req -new -key server.key -out server.csr \
  -subj "/C=TW/ST=Taiwan/L=Taipei/O=MQTT-Gear/CN=localhost"

# 用 CA 簽署服務器憑證
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt -days 365

# 設置權限
chmod 600 server.key
chmod 644 server.crt ca.crt

# 清理臨時文件
rm server.csr ca.key ca.srl
```

## 啟用 TLS

1. 將憑證文件放入此目錄
2. 修改客戶端代碼連接端口為 8883
3. 在客戶端代碼中添加：
   ```python
   client.tls_set(ca_certs="broker/certs/ca.crt")
   ```

## 注意事項

- 自簽名憑證僅適用於開發測試
- 生產環境建議使用可信任的 CA 簽發憑證
- 確保 CN 字段匹配實際的服務器地址
