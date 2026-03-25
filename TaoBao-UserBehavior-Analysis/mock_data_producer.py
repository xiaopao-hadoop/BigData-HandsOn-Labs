import json
import time
import datetime
import os
from kafka import KafkaProducer

CSV_FILE_PATH = r"path"
# 可选： 创建一个offset文件保留上次python发到哪一行了 
OFFSET_FILE = r"path\offset.txt" 

# Kafka 节点的真实 IP
KAFKA_BROKER = '192.168.144.101:9092'
TOPIC_NAME = 'ods_user_behavior'

# 每发送 10000 条记录，执行一次 offset 写入
BATCH_SAVE_OFFSET = 10000  

def get_last_offset():
    """读取上一次成功发送的行号"""
    if os.path.exists(OFFSET_FILE):
        with open(OFFSET_FILE, 'r') as f:
            try:
                return int(f.read().strip())
            except ValueError:
                return 0
    return 0

def save_offset(offset):
    """将当前行号保存到本地"""
    with open(OFFSET_FILE, 'w') as f:
        f.write(str(offset))

def main():
    print("[*] 正在连接 Kafka 集群...")
    # 初始化 Kafka Producer
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BROKER,
        # 将字典序列化为 JSON 并转为 UTF-8 字节流
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        # 将 Key 序列化为 UTF-8 字节流
        key_serializer=lambda k: str(k).encode('utf-8'),
        batch_size=16384,  # 开启批处理，满 16KB 发送一次
        linger_ms=50,
        api_version=(3, 0, 0)
    )

    start_offset = get_last_offset()
    print(f"[*] 连接成功！当前将从第 {start_offset} 行开始读取...")

    last_timestamp = None
    current_line = 0

    try:
        with open(CSV_FILE_PATH, 'r', encoding='utf-8') as f:
            for line in f:
                # 快速跳过已经发送过的行
                if current_line < start_offset:
                    current_line += 1
                    continue

                # 解析 CSV 行数据 (用户ID, 商品ID, 商品类目ID, 行为类型, 时间戳)
                parts = line.strip().split(',')
                if len(parts) != 5:
                    current_line += 1
                    continue

                user_id, item_id, category_id, behavior, ts_str = parts

                try:
                    ts_int = int(ts_str)
                    # 防御策略：避免程序异常退出，可以自己适当修改
                    if ts_int < 900000000 or ts_int > 2000000000:
                        current_line += 1
                        continue
                    event_time = datetime.datetime.fromtimestamp(ts_int).strftime('%Y-%m-%d %H:%M:%S')
                    
                except (ValueError, OSError, OverflowError):
                    # 遇到时间戳解析错误，直接静默跳过
                    current_line += 1
                    continues

                # 转换时间戳为可读格式
                event_time = datetime.datetime.fromtimestamp(ts_int).strftime('%Y-%m-%d %H:%M:%S')

                # 封装为 JSON 字典
                data = {
                    "user_id": user_id,
                    "item_id": item_id,
                    "category_id": category_id,
                    "behavior": behavior,
                    "ts": ts_int,
                    "event_time": event_time
                }

                # 计算与上一条数据的时间差，模拟真实发送频率，这里注释是因为发送速度太慢了，可以选择下面每2000条休眠0.05s加快速度也避免程序奔溃
                """
                if last_timestamp is not None:
                    time_diff = ts_int - last_timestamp
                    if time_diff > 0:
                        sleep_time = min(time_diff / 100.0, 0.5)
                        time.sleep(sleep_time)
                last_timestamp = ts_int
                """
                if current_line % 2000 == 0:
                    time.sleep(0.05)

                # 发送数据到 Kafka，以 user_id 为 key 保证单用户行为局部有序
                producer.send(TOPIC_NAME, key=user_id, value=data)

                current_line += 1

                # 定期打印进度并保存 offset
                if current_line % BATCH_SAVE_OFFSET == 0:
                    producer.flush() 
                    save_offset(current_line)
                    print(f"[*] 已成功发送并记录至第 {current_line} 行...")

    except KeyboardInterrupt:
        # 捕获 Ctrl+C 中断信号
        print("\n[!] 检测到手动中断 (Ctrl+C)，正在保存进度并退出...")
    except Exception as e:
        print(f"\n[X] 发生异常: {e}")
    finally:
        # 无论程序正常结束还是异常崩溃，退出前都要确保最后的数据发送完毕并保存最终 offset
        print("[*] 正在保存当前行号...")
        producer.flush()
        save_offset(current_line)
        producer.close()
        print(f"[*] 程序已安全退出，最终停留行号: {current_line}")

if __name__ == '__main__':
    main()