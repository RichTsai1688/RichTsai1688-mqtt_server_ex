#!/usr/bin/env python3
"""
MQTT Gear Server 監控工具
監聽所有系統消息並提供即時狀態顯示
"""

import json
import time
import argparse
from datetime import datetime
import paho.mqtt.client as mqtt

# MQTT 配置 - 可通過環境變數覆蓋
import os
BROKER_HOST = os.getenv("MQTT_BROKER_IP", "140.134.60.218")
PORT = int(os.getenv("MQTT_PORT", "4883"))
CLIENT_ID = "monitor"
USER = os.getenv("MQTT_A_USER", "A_user")  # 使用 A_user 權限監控
PASS = os.getenv("MQTT_A_PASSWORD", "A_password")

# Topic 定義
ID = "id1"
TOPICS = [
    f"v1/{ID}/ctrl/#",
    f"v1/{ID}/cmd/#", 
    f"v1/{ID}/telemetry/#",
    f"v1/{ID}/config/#",
    f"v1/{ID}/status"
]

class MQTTMonitor:
    def __init__(self, verbose=False):
        self.verbose = verbose
        self.message_count = 0
        self.start_time = time.time()
        self.last_messages = {}
        
    def setup_client(self):
        """設置 MQTT 客戶端"""
        self.client = mqtt.Client(client_id=CLIENT_ID, clean_session=True)
        self.client.username_pw_set(USER, PASS)
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
        
    def on_connect(self, client, userdata, flags, rc):
        """連接回調"""
        if rc == 0:
            print(f"✓ 監控器已連接到 {BROKER_HOST}:{PORT}")
            print("正在訂閱監控主題...")
            
            for topic in TOPICS:
                client.subscribe(topic, qos=1)
                print(f"  - {topic}")
                
            print(f"\n{'='*60}")
            print(f"{'時間':<12} {'Topic':<25} {'發送者':<8} {'類型':<15} {'內容'}")
            print(f"{'='*60}")
        else:
            print(f"✗ 連接失敗，錯誤碼: {rc}")
            
    def on_message(self, client, userdata, msg):
        """消息回調"""
        self.message_count += 1
        
        try:
            # 解析消息
            payload = msg.payload.decode('utf-8')
            data = json.loads(payload) if payload else {}
            
            # 提取信息
            timestamp = datetime.now().strftime("%H:%M:%S")
            topic = msg.topic.split('/')[-1]  # 只顯示最後一部分
            sender = data.get('sender', '?')
            msg_type = data.get('type', 'unknown')
            
            # 格式化內容
            content = self._format_content(data, msg.topic)
            
            # 顯示消息
            print(f"{timestamp:<12} {topic:<25} {sender:<8} {msg_type:<15} {content}")
            
            # 詳細模式顯示完整數據
            if self.verbose:
                print(f"  完整數據: {json.dumps(data, ensure_ascii=False)}")
                print(f"  QoS: {msg.qos}, Retained: {msg.retain}")
                print()
                
            # 記錄最新消息
            self.last_messages[msg.topic] = {
                'timestamp': time.time(),
                'data': data,
                'qos': msg.qos,
                'retained': msg.retain
            }
            
        except json.JSONDecodeError:
            # 非 JSON 消息
            timestamp = datetime.now().strftime("%H:%M:%S")
            print(f"{timestamp:<12} {msg.topic:<25} {'?':<8} {'raw':<15} {msg.payload.decode('utf-8', errors='ignore')}")
        except Exception as e:
            print(f"解析消息錯誤: {e}")
            
    def _format_content(self, data, topic):
        """格式化消息內容顯示"""
        if 'point' in data:
            point = data['point']
            return f"({point.get('x', '?')}, {point.get('y', '?')})"
        elif 'values' in data:
            values = data['values']
            return f"{len(values)}個特徵值"
        elif 'online' in data:
            status = "上線" if data['online'] else "離線"
            state = data.get('state', '')
            return f"{status} [{state}]"
        elif 'job_id' in data:
            return f"作業ID: {data['job_id'][:8]}..."
        elif 'parameters' in data:
            return "系統配置"
        elif 'summary' in data:
            summary = data['summary']
            return f"完成 {summary.get('successful_points', '?')}/{summary.get('total_points', '?')}"
        else:
            # 顯示前50個字符
            content = str(data).replace('\n', ' ').replace('\t', ' ')
            return content[:50] + "..." if len(content) > 50 else content
            
    def print_statistics(self):
        """打印統計信息"""
        runtime = time.time() - self.start_time
        print(f"\n{'='*60}")
        print(f"監控統計:")
        print(f"  運行時間: {runtime:.1f} 秒")
        print(f"  收到消息: {self.message_count} 條")
        print(f"  平均速率: {self.message_count/runtime:.2f} 條/秒" if runtime > 0 else "  平均速率: 0 條/秒")
        
        # 顯示最新狀態
        if self.last_messages:
            print(f"\n最新狀態:")
            for topic, info in self.last_messages.items():
                age = time.time() - info['timestamp']
                print(f"  {topic}: {age:.1f}秒前")
                
    def start_monitoring(self):
        """開始監控"""
        try:
            if self.client.connect(BROKER_HOST, PORT, keepalive=60) == 0:
                self.client.loop_forever()
            else:
                print("無法連接到 MQTT Broker")
        except KeyboardInterrupt:
            print("\n收到中斷信號，正在停止監控...")
            self.print_statistics()
        except Exception as e:
            print(f"監控錯誤: {e}")
        finally:
            self.client.disconnect()

def main():
    parser = argparse.ArgumentParser(description="MQTT Gear Server 監控工具")
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='顯示詳細消息內容'
    )
    
    parser.add_argument(
        '--host', 
        default=BROKER_HOST,
        help=f'MQTT Broker 地址 (默認: {BROKER_HOST})'
    )
    
    parser.add_argument(
        '--port',
        type=int, 
        default=PORT,
        help=f'MQTT Broker 端口 (默認: {PORT})'
    )
    
    args = parser.parse_args()
    
    # 更新全局配置
    global BROKER_HOST, PORT
    BROKER_HOST = args.host
    PORT = args.port
    
    print("=== MQTT Gear Server 監控器 ===")
    print(f"Broker: {BROKER_HOST}:{PORT}")
    print(f"監控 ID: {ID}")
    print("按 Ctrl+C 停止監控\n")
    
    monitor = MQTTMonitor(verbose=args.verbose)
    monitor.setup_client()
    monitor.start_monitoring()

if __name__ == "__main__":
    main()
