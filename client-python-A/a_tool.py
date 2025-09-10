#!/usr/bin/env python3
"""
MQTT Gear Server - A 端演算法客戶端工具
提供命令行界面來控制和監控系統
"""

import argparse
import json
import time
import sys
import logging
from a_client import MQTTClient, logger

def run_interactive_mode():
    """互動模式 - 手動輸入點位"""
    print("=== 互動模式 ===")
    print("輸入點位座標，按 Ctrl+C 退出")
    
    client = MQTTClient()
    client.setup_client()
    
    if not client.connect():
        print("無法連接到 MQTT Broker")
        return
        
    # 在背景啟動 MQTT 循環
    import threading
    mqtt_thread = threading.Thread(target=client.start_loop, daemon=True)
    mqtt_thread.start()
    
    # 等待連接建立
    time.sleep(2)
    
    try:
        while True:
            print("\n請輸入點位座標 (格式: x,y) 或 'quit' 退出:")
            user_input = input("> ").strip()
            
            if user_input.lower() in ['quit', 'q', 'exit']:
                break
                
            try:
                x, y = map(float, user_input.split(','))
                print(f"發送點位: ({x}, {y})")
                
                result = client.send_point_and_wait(x, y, timeout=10.0, retries=1)
                if result:
                    print(f"✓ 成功收到結果:")
                    print(f"  特徵數量: {len(result.get('features', []))}")
                    print(f"  數值範圍: {min(result.get('values', [0])):.3f} ~ {max(result.get('values', [0])):.3f}")
                else:
                    print("✗ 未收到結果")
                    
            except ValueError:
                print("錯誤: 請輸入正確格式 (例: 10.5,-7.2)")
            except Exception as e:
                print(f"錯誤: {e}")
                
    except KeyboardInterrupt:
        print("\n正在退出...")
    finally:
        client.disconnect()

def run_batch_mode(points_file: str):
    """批次模式 - 從文件讀取點位"""
    print(f"=== 批次模式 - 讀取文件: {points_file} ===")
    
    try:
        with open(points_file, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"錯誤: 找不到文件 {points_file}")
        return
    except Exception as e:
        print(f"錯誤: 無法讀取文件 {e}")
        return
    
    # 解析點位
    points = []
    for i, line in enumerate(lines, 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        try:
            x, y = map(float, line.split(','))
            points.append((x, y))
        except ValueError:
            print(f"警告: 第 {i} 行格式錯誤，跳過: {line}")
    
    if not points:
        print("錯誤: 沒有找到有效的點位")
        return
        
    print(f"找到 {len(points)} 個點位")
    
    # 執行批次處理
    client = MQTTClient()
    client.setup_client()
    
    if not client.connect():
        print("無法連接到 MQTT Broker")
        return
        
    # 在背景啟動 MQTT 循環
    import threading
    mqtt_thread = threading.Thread(target=client.start_loop, daemon=True)
    mqtt_thread.start()
    
    # 等待連接建立
    time.sleep(2)
    
    results = []
    successful = 0
    
    try:
        for i, (x, y) in enumerate(points, 1):
            print(f"[{i}/{len(points)}] 處理點位 ({x}, {y})...")
            
            try:
                result = client.send_point_and_wait(x, y, timeout=10.0, retries=2)
                if result:
                    results.append({
                        'point': {'x': x, 'y': y},
                        'result': result,
                        'status': 'success'
                    })
                    successful += 1
                    print(f"  ✓ 成功")
                else:
                    results.append({
                        'point': {'x': x, 'y': y},
                        'status': 'timeout'
                    })
                    print(f"  ✗ 逾時")
                    
            except Exception as e:
                results.append({
                    'point': {'x': x, 'y': y},
                    'status': 'error',
                    'error': str(e)
                })
                print(f"  ✗ 錯誤: {e}")
            
            # 點位間間隔
            if i < len(points):
                time.sleep(1)
                
    except KeyboardInterrupt:
        print("\n收到中斷信號，正在停止...")
    finally:
        client.disconnect()
        
        # 輸出總結
        print(f"\n=== 批次處理完成 ===")
        print(f"總點位數: {len(points)}")
        print(f"成功: {successful}")
        print(f"失敗: {len(points) - successful}")
        
        # 保存結果到文件
        output_file = f"batch_results_{int(time.time())}.json"
        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump({
                    'timestamp': time.time(),
                    'summary': {
                        'total': len(points),
                        'successful': successful,
                        'failed': len(points) - successful
                    },
                    'results': results
                }, f, indent=2, ensure_ascii=False)
            print(f"結果已保存到: {output_file}")
        except Exception as e:
            print(f"警告: 無法保存結果文件: {e}")

def generate_sample_points(output_file: str):
    """生成範例點位文件"""
    points = [
        "# MQTT Gear Server 範例點位文件",
        "# 格式: x,y (每行一個點位)",
        "# 井字形掃描模式",
        "0,0",
        "10,0", 
        "20,0",
        "0,10",
        "10,10",
        "20,10", 
        "0,20",
        "10,20",
        "20,20",
        "# 對角線",
        "5,5",
        "15,15",
        "-5,-5",
        "-10,-10"
    ]
    
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(points) + '\n')
        print(f"範例點位文件已生成: {output_file}")
        print("您可以編輯此文件後使用 --batch 模式執行")
    except Exception as e:
        print(f"錯誤: 無法生成文件 {e}")

def main():
    parser = argparse.ArgumentParser(
        description="MQTT Gear Server A端控制工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
範例用法:
  %(prog)s                          # 啟動正常模式 (等待 B 端觸發)
  %(prog)s --interactive            # 互動模式 (手動輸入點位)
  %(prog)s --batch points.txt       # 批次模式 (從文件讀取)
  %(prog)s --generate sample.txt    # 生成範例點位文件
        """
    )
    
    parser.add_argument(
        '--interactive', '-i',
        action='store_true',
        help='啟動互動模式，手動輸入點位'
    )
    
    parser.add_argument(
        '--batch', '-b',
        metavar='FILE',
        help='批次模式，從指定文件讀取點位 (格式: x,y 每行一個)'
    )
    
    parser.add_argument(
        '--generate', '-g',
        metavar='FILE',  
        help='生成範例點位文件'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='顯示詳細日誌'
    )
    
    args = parser.parse_args()
    
    # 設置日誌級別
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # 根據參數執行不同模式
    if args.generate:
        generate_sample_points(args.generate)
    elif args.interactive:
        run_interactive_mode()
    elif args.batch:
        run_batch_mode(args.batch)
    else:
        # 正常模式
        print("=== 正常模式 - 等待 B 端觸發 START 信號 ===")
        from a_client import main as normal_main
        normal_main()

if __name__ == "__main__":
    main()
