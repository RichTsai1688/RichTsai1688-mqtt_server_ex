#!/usr/bin/env python3
"""
B 客戶端模擬器
用於測試與 A 客戶端的 MQTT 通信
"""

import json
import time
import uuid
import threading
import logging
import random
from typing import Dict, Any, Optional
import paho.mqtt.client as mqtt

# 配置日誌
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# MQTT 配置 - 與 A 客戶端保持一致
import os
BROKER_HOST = os.getenv("MQTT_BROKER_IP", "140.134.60.218")
PORT = int(os.getenv("MQTT_PORT", "4883"))
ID = os.getenv("MQTT_CLIENT_ID", "id1")
CLIENT_ID = f"B-{ID}"
KEEPALIVE = int(os.getenv("MQTT_KEEPALIVE", "45"))

# Topic 定義 - 與 A 客戶端對應
TOP_CTRL_START = f"v1/{ID}/ctrl/start"       # B→A
TOP_CTRL_END   = f"v1/{ID}/ctrl/end"         # A→B
TOP_CMD_POINT  = f"v1/{ID}/cmd/point"        # A→B
TOP_RESULT     = f"v1/{ID}/telemetry/result" # B→A
TOP_SETTING    = f"v1/{ID}/config/setting"   # retained
TOP_STATUS     = f"v1/{ID}/status"

class BMQTTClient:
    def __init__(self):
        self.client = None
        self.is_connected = False
        self.processing_delay = 2.0  # 模擬處理時間（秒）
        
    def setup_client(self):
        """設置 MQTT 客戶端"""
        self.client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2, 
            client_id=CLIENT_ID, 
            clean_session=False, 
            protocol=mqtt.MQTTv311
        )
        
        # 設置遺囑
        will_payload = json.dumps({
            "online": False, 
            "sender": "B", 
            "ts": int(time.time()),
            "state": "disconnected"
        })
        self.client.will_set(TOP_STATUS, will_payload, qos=1, retain=True)
        
        # 設置回調函數
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
        self.client.on_disconnect = self.on_disconnect
        
    def on_connect(self, client: mqtt.Client, userdata, flags, rc, properties=None):
        """連接成功回調"""
        if rc == 0:
            self.is_connected = True
            logger.info("B 客戶端連接成功")
            
            # 訂閱主題
            subs = [
                (TOP_CTRL_END, 1),   # 監聽 A 端結束信號
                (TOP_CMD_POINT, 1),  # 監聽 A 端點位命令
                (TOP_STATUS, 1)      # 監聽狀態更新
            ]
            client.subscribe(subs)
            
            # 發送上線狀態（retained）
            status_payload = json.dumps({
                "online": True, 
                "sender": "B", 
                "ts": int(time.time()), 
                "state": "ready"
            })
            client.publish(TOP_STATUS, status_payload, qos=1, retain=True)
            logger.info("B 客戶端已發送上線狀態")
            
            # 發送初始設定（retained）
            self.send_initial_settings()
            
        else:
            logger.error(f"B 客戶端連接失敗，錯誤碼：{rc}")
            
    def on_disconnect(self, client, userdata, rc, properties=None):
        """斷線回調"""
        self.is_connected = False
        logger.warning(f"B 客戶端斷線，錯誤碼：{rc}")
        
    def on_message(self, client: mqtt.Client, userdata, msg: mqtt.MQTTMessage):
        """接收消息回調"""
        try:
            data = json.loads(msg.payload.decode("utf-8"))
            logger.info(f"B 收到消息 - Topic: {msg.topic}, Data: {data}")
        except Exception as e:
            logger.error(f"B 解析消息錯誤: {e}, topic: {msg.topic}")
            return

        # 處理點位命令
        if msg.topic == TOP_CMD_POINT and data.get("type") == "move_point":
            threading.Thread(
                target=self.process_point_command, 
                args=(data,), 
                daemon=True
            ).start()

        # 處理結束信號
        elif msg.topic == TOP_CTRL_END and data.get("type") == "end":
            logger.info(f"[B] 收到 A 端結束信號: {data}")
            
        # 處理狀態消息
        elif msg.topic == TOP_STATUS:
            sender = data.get("sender")
            if sender == "A":
                logger.info(f"[B] A 端狀態: {data.get('state')}")
                
    def send_initial_settings(self):
        """發送初始設定到 retained topic"""
        settings = {
            "version": "1.0",
            "features": ["temperature", "pressure", "vibration", "speed"],
            "sampling_rate": 100,
            "precision": 0.01,
            "sender": "B",
            "ts": int(time.time())
        }
        
        self.client.publish(TOP_SETTING, json.dumps(settings), qos=1, retain=True)
        logger.info("[B] 已發送初始設定")
        
    def process_point_command(self, data: Dict[str, Any]):
        """處理點位命令並回傳結果"""
        req_id = data.get("req_id")
        point = data.get("point", {})
        x = point.get("x", 0)
        y = point.get("y", 0)
        
        logger.info(f"[B] 開始處理點位 ({x},{y}), req_id={req_id}")
        
        # 模擬處理時間
        time.sleep(self.processing_delay)
        
        # 生成模擬數據
        features = ["temperature", "pressure", "vibration", "speed"]
        values = [
            round(20 + random.uniform(-5, 15), 2),  # temperature
            round(1013 + random.uniform(-50, 50), 1),  # pressure
            round(random.uniform(0, 10), 3),  # vibration
            round(random.uniform(10, 100), 1)  # speed
        ]
        
        # 添加一些基於座標的變化
        values[0] += abs(x) * 0.1  # 溫度隨 x 變化
        values[1] += abs(y) * 0.5  # 壓力隨 y 變化
        
        result_payload = {
            "type": "result_feature_set",
            "req_id": req_id,
            "point": {"x": x, "y": y},
            "features": features,
            "values": values,
            "metadata": {
                "processing_time": self.processing_delay,
                "quality": "good",
                "sensor_status": "normal"
            },
            "ts": int(time.time()),
            "sender": "B"
        }
        
        # 發送結果
        self.client.publish(TOP_RESULT, json.dumps(result_payload), qos=1)
        logger.info(f"[B] 已發送結果 req_id={req_id}, 特徵數: {len(features)}")

    def send_start_signal(self):
        """發送開始信號給 A 端"""
        if not self.is_connected:
            logger.error("MQTT 未連接，無法發送開始信號")
            return False
            
        start_payload = {
            "type": "start",
            "session_id": str(uuid.uuid4()),
            "ts": int(time.time()),
            "sender": "B",
            "config": {
                "max_points": 10,
                "timeout": 30
            }
        }
        
        self.client.publish(TOP_CTRL_START, json.dumps(start_payload), qos=1)
        logger.info("[B] 已發送 START 信號給 A 端")
        return True

    def connect(self):
        """連接到 MQTT Broker"""
        try:
            logger.info(f"B 正在連接到 MQTT Broker {BROKER_HOST}:{PORT}")
            self.client.connect(BROKER_HOST, PORT, keepalive=KEEPALIVE)
            return True
        except Exception as e:
            logger.error(f"B 連接 MQTT Broker 失敗: {e}")
            return False
            
    def disconnect(self):
        """斷開連接"""
        if self.client and self.is_connected:
            # 發送離線狀態
            status_payload = json.dumps({
                "online": False, 
                "sender": "B", 
                "ts": int(time.time()),
                "state": "disconnected"
            })
            self.client.publish(TOP_STATUS, status_payload, qos=1, retain=True)
            self.client.disconnect()

def main():
    """主函數"""
    b_client = BMQTTClient()
    
    try:
        # 設置客戶端
        b_client.setup_client()
        
        # 連接
        if b_client.connect():
            logger.info("B 客戶端啟動成功")
            
            # 開始 MQTT 循環（非阻塞）
            b_client.client.loop_start()
            
            # 等待連接建立
            time.sleep(2)
            
            # 互動式控制
            print("\n=== B 客戶端控制台 ===")
            print("指令:")
            print("  s - 發送 START 信號給 A 端")
            print("  q - 退出")
            print("  h - 顯示幫助")
            
            while True:
                try:
                    cmd = input("\n輸入指令: ").strip().lower()
                    
                    if cmd == 's':
                        b_client.send_start_signal()
                    elif cmd == 'q':
                        break
                    elif cmd == 'h':
                        print("指令:")
                        print("  s - 發送 START 信號給 A 端")
                        print("  q - 退出")
                        print("  h - 顯示幫助")
                    else:
                        print("未知指令，輸入 'h' 查看幫助")
                        
                except KeyboardInterrupt:
                    break
                    
            b_client.client.loop_stop()
        else:
            logger.error("無法啟動 B 客戶端")
            
    except Exception as e:
        logger.error(f"B 客戶端運行錯誤: {e}")
    finally:
        b_client.disconnect()
        logger.info("B 客戶端已關閉")

if __name__ == "__main__":
    main()
