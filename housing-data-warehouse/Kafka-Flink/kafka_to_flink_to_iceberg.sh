#!/bin/bash

# 描述: 启动 Flink YARN Session 并执行 SQL 将 Kafka 数据写入 Iceberg

# 定义临时 SQL 文件的存放路径
SQL_FILE="/tmp/kafka_to_iceberg_job.sql"

echo "====================  启动 Flink YARN Session ===================="
# 启动 Yarn Session 
yarn-session.sh -nm flink-session -d -s 2 -jm 1024 -tm 2048
echo "等待 YARN Session 初始化完成 (15秒)..."
sleep 15

echo "====================  生成 Flink SQL 执行逻辑 ===================="
# 使用 cat 和 EOF 动态生成 SQL 文件
cat > $SQL_FILE << 'EOF'

-- 1. 使用Flink 默认的内存 Catalog(自定义的catalog无法消费Kafka消息)
USE CATALOG default_catalog;

-- 2. 建立 Kafka 源表
CREATE TABLE kafka_source_in_memory (
  `header` ROW<`source` STRING, `event_time` BIGINT, `version` STRING, `trace_id` STRING, `batch_id` STRING>,
  `core_data` ROW<`house_id` STRING, `house_url` STRING, `title` STRING, `city` STRING, `district` STRING, `neighborhood` STRING, `community` STRING, `total_price` DOUBLE, `unit_price` INT, `area_sqm` DOUBLE, `room_num` INT, `hall_num` INT, `bathroom_num` INT, `orientation` STRING, `floor_level` STRING, `floor_total` INT, `decoration` STRING, `build_year` INT>,
  `ext_attributes` ROW<`tags` ARRAY<STRING>, `follow_info` ROW<`attention_count` INT, `visit_30_days` INT>, `subway_info` STRING, `raw_info` ROW<`p1_desc` STRING, `p2_desc` STRING>>
) WITH (
  'connector' = 'kafka',
  'topic' = 'ershoufang_topic', 
  'properties.bootstrap.servers' = 'lake-master-01:9092,lake-worker-01:9092,lake-worker-02:9092',
  'properties.group.id' = 'live_stream_group_final', 
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'json',
  'json.ignore-parse-errors' = 'true'
);

-- 3. 建立数据湖 Iceberg Catalog
CREATE CATALOG iceberg_catalog WITH (
  'type' = 'iceberg',
  'catalog-type' = 'hive',
  'uri' = 'thrift://lake-master-01:9083'
);

CREATE DATABASE IF NOT EXISTS iceberg_catalog.ershoufang;

-- 4. 建立数据湖表 (ODS层)
CREATE TABLE IF NOT EXISTS iceberg_catalog.ershoufang.ods_ershoufang (
  `house_id` STRING,
  `source` STRING,
  `event_time` BIGINT,
  `version` STRING,
  `trace_id` STRING,
  `batch_id` STRING,
  `house_url` STRING,
  `title` STRING,
  `city` STRING,
  `district` STRING,
  `neighborhood` STRING,
  `community` STRING,
  `total_price` DOUBLE,
  `unit_price` INT,
  `area_sqm` DOUBLE,
  `room_num` INT,
  `hall_num` INT,
  `bathroom_num` INT,
  `orientation` STRING,
  `floor_level` STRING,
  `floor_total` INT,
  `decoration` STRING,
  `build_year` INT,
  `tags` ARRAY<STRING>,
  `attention_count` INT,
  `visit_30_days` INT,
  `subway_info` STRING,
  `raw_p1_desc` STRING,
  `raw_p2_desc` STRING,
  `etl_time` TIMESTAMP(3),
  PRIMARY KEY (`house_id`, `city`) NOT ENFORCED
) PARTITIONED BY (`city`) 
WITH (
  'format-version' = '2', 
  'write.upsert.enabled' = 'true', 
  'write.metadata.delete-after-commit.enabled' = 'true', 
  'write.metadata.previous-versions-max' = '5'
);

-- 5. 设置流模式和 Checkpoint (Iceberg 强依赖 Checkpoint 来提交 Snapshot)
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '10000';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';

-- 6. 执行流式插入
INSERT INTO iceberg_catalog.ershoufang.ods_ershoufang
SELECT 
  core_data.house_id,
  header.`source`, header.event_time, header.version, header.trace_id, header.batch_id,
  core_data.house_url, core_data.title, core_data.city, core_data.district, core_data.neighborhood, core_data.community, core_data.total_price, core_data.unit_price, core_data.area_sqm, core_data.room_num, core_data.hall_num, core_data.bathroom_num, core_data.orientation, core_data.floor_level, core_data.floor_total, core_data.decoration, core_data.build_year,
  ext_attributes.tags, ext_attributes.follow_info.attention_count, ext_attributes.follow_info.visit_30_days, ext_attributes.subway_info, ext_attributes.raw_info.p1_desc AS raw_p1_desc, ext_attributes.raw_info.p2_desc AS raw_p2_desc,
  CURRENT_TIMESTAMP AS etl_time
FROM default_catalog.default_database.kafka_source_in_memory
WHERE core_data.house_id IS NOT NULL;

EOF

echo "==================== 提交 Flink SQL 任务 ===================="
# 非交互式执行 SQL 脚本
/opt/module/flink-1.17.2/bin/sql-client.sh -f $SQL_FILE

echo "清理临时 SQL 文件..."
rm -f $SQL_FILE
echo "请前往 YARN UI (http://lake-master-01:8088) 确认 Flink 任务已处于 RUNNING 状态！"