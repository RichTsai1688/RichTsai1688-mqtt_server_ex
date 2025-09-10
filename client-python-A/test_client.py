import ssl, time, logging
import paho.mqtt.client as mqtt
from paho.mqtt.enums import CallbackAPIVersion

BROKER_HOST = "140.134.60.218"
BROKER_PORT = 4883             # 確認你真的要連這個埠（見 B 區）
USERNAME    = "A_user"
PASSWORD    = "admin1234"
CLIENT_ID   = "client-A-001"

logging.basicConfig(level=logging.INFO)

def on_connect(client, userdata, flags, reason_code, properties=None):
    if reason_code.is_success:
        logging.info("已連上 MQTT Broker")
    else:
        logging.error(f"連線失敗: {reason_code} ({reason_code.value})")

def on_disconnect(client, userdata, reason_code, properties=None):
    logging.warning(f"斷線: {reason_code}")

client = mqtt.Client(
    CallbackAPIVersion.VERSION2,   # ← 使用新版回呼 API
    client_id=CLIENT_ID,
    protocol=mqtt.MQTTv311
)

# v2：不要再用 clean_session；改用 clean_start + session_expiry
# client.clear_socket()  # 保守作法，確保乾淨 socket
client.reconnect_delay_set(min_delay=1, max_delay=30)
client.username_pw_set(USERNAME, PASSWORD)

# 若該埠需要 TLS，請開啟（見 B 區第 4 點）；若是純 TCP，請註解掉以下三行
# client.tls_set(ca_certs="/path/ca.crt", certfile=None, keyfile=None, cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLS_CLIENT)
# client.tls_insecure_set(False)
# # 若 broker 要求 SNI/主機名，請確保連線主機名與證書一致（或改用 IP+subjectAltName ）

client.on_connect = on_connect
client.on_disconnect = on_disconnect

try:
    logging.info(f"正在連接到 MQTT Broker {BROKER_HOST}:{BROKER_PORT}")
    client.connect(BROKER_HOST, BROKER_PORT, keepalive=60)
    client.loop_start()
    # 你的主流程...
    time.sleep(3)
except Exception as e:
    logging.exception(f"連接 MQTT Broker 失敗: {e}")
