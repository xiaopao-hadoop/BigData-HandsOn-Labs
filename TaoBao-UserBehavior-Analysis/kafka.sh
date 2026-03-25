#!/bin/bash

# ==========================================
# Component: Kafka Topic Setup & Verification
# ==========================================

# 1. 定义全局变量 (根据实际情况修改)
BOOTSTRAP_SERVER="lake-master-01:9092"
TOPIC_NAME="ods_user_behavior"

# 2. 创建 Kafka Topic
# 参数说明: 2个分区, 3个副本
./kafka-topics.sh --create \
  --bootstrap-server $BOOTSTRAP_SERVER \
  --topic $TOPIC_NAME \
  --partitions 2 \
  --replication-factor 3

# 3. 验证 Topic 配置是否成功
./kafka-topics.sh --describe \
  --bootstrap-server $BOOTSTRAP_SERVER \
  --topic $TOPIC_NAME

# 4. 启动控制台消费者(验证数据写入情况)
./kafka-console-consumer.sh \
  --bootstrap-server $BOOTSTRAP_SERVER \
  --topic $TOPIC_NAME \
  --property print.key=true \
  --property key.separator="-"