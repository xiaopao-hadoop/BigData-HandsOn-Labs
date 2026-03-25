# 进入目录
cd /opt/module/flink-1.17.2/bin/

# 以后台模式在 YARN 上启动一个 Flink Session
./yarn-session.sh -d -jm 1024m -tm 2048m -s 2 -nm taobao_flink_session

# 启动 Flink SQL 命令行客户端
./sql-client.sh

# 以下在flinksql运行

# 开启 Checkpoint 
SET 'execution.checkpointing.interval' = '1min';
SET 'pipeline.name' = 'taobao_behavior_lakehouse_etl';

# 在默认 Catalog 创建临时表，映射 Kafka (退出终端即消失，仅作为数据入口)
CREATE TEMPORARY TABLE default_catalog.default_database.kafka_source_user_behavior (
    user_id STRING,
    item_id STRING,
    category_id STRING,
    behavior STRING,
    ts BIGINT,
    event_time STRING,
    ts_ltz AS TO_TIMESTAMP(event_time, 'yyyy-MM-dd HH:mm:ss'),
    WATERMARK FOR ts_ltz AS ts_ltz - INTERVAL '3' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'ods_user_behavior',
    'properties.bootstrap.servers' = 'lake-master-01:9092', 
    'properties.group.id' = 'flink_lake_group',
    'scan.startup.mode' = 'earliest-offset', 
    'format' = 'json'
);

# 创建并切换到 Iceberg Catalog (对接 Hive Metastore)
CREATE CATALOG taobao_lake WITH (
    'type'='iceberg',
    'catalog-type'='hive',
    'uri'='thrift://lake-master-01:9083', 
    'clients'='5',
    'property-version'='1',
    'warehouse'='hdfs://lake-master-01:8020/user/hive/warehouse/taobao'
);

USE CATALOG taobao_lake;
CREATE DATABASE IF NOT EXISTS db_ecommerce;
USE db_ecommerce;

# 1. 创建 ODS 层 (原始数据)
CREATE TABLE ods_user_behavior (
    user_id STRING,
    item_id STRING,
    category_id STRING,
    behavior STRING,
    ts BIGINT,
    event_time STRING,  
    ts_ltz TIMESTAMP(3),
    dt DATE  
) PARTITIONED BY (dt)  
WITH (
    'write.target-file-size-bytes'='134217728'
);

-- 2. 创建 DWD 层 
CREATE TABLE dwd_user_behavior (
    user_id STRING,
    item_id STRING,
    category_id STRING,
    behavior STRING,
    ts BIGINT,
    ts_ltz TIMESTAMP(3),
    dt DATE  
) PARTITIONED BY (dt)
WITH (
    'write.target-file-size-bytes'='134217728'
);

# 3. 创建 DWS 层 (Iceberg 聚合层，存放 10 分钟窗口统计结果)
CREATE TABLE dws_category_metrics (
    win_start TIMESTAMP(3),
    win_end TIMESTAMP(3),
    category_id STRING,
    pv_cnt BIGINT,
    cart_cnt BIGINT,
    fav_cnt BIGINT,
    buy_cnt BIGINT
) WITH (
    'write.target-file-size-bytes'='134217728'
);

# 4. 统计每种点击的实时点击量
CREATE TABLE dws_behavior_funnel (
    win_start TIMESTAMP(3),
    win_end TIMESTAMP(3),
    behavior STRING,
    step_name STRING,
    trigger_cnt BIGINT
) WITH (
    'write.target-file-size-bytes'='134217728'
);

# 5. 执行flink流处理
EXECUTE STATEMENT SET
BEGIN

    # 任务 A：贴源层 (ODS)
    INSERT INTO taobao_lake.db_ecommerce.ods_user_behavior
    SELECT 
        user_id, item_id, category_id, behavior, ts, event_time, ts_ltz,
        CAST(ts_ltz AS DATE) AS dt 
    FROM default_catalog.default_database.kafka_source_user_behavior;

    # 任务 B：明细层 (DWD)
    INSERT INTO taobao_lake.db_ecommerce.dwd_user_behavior
    SELECT 
        user_id, item_id, category_id, behavior, ts, ts_ltz,
        CAST(ts_ltz AS DATE) AS dt
    FROM default_catalog.default_database.kafka_source_user_behavior
    WHERE behavior IS NOT NULL AND behavior IN ('pv', 'buy', 'cart', 'fav');

    # 任务 C：品类指标预聚合层 (DWS)
    INSERT INTO taobao_lake.db_ecommerce.dws_category_metrics
    SELECT 
        TUMBLE_START(ts_ltz, INTERVAL '10' MINUTE) AS win_start,
        TUMBLE_END(ts_ltz, INTERVAL '10' MINUTE) AS win_end,
        category_id,
        SUM(CASE WHEN behavior = 'pv' THEN 1 ELSE 0 END) AS pv_cnt,
        SUM(CASE WHEN behavior = 'cart' THEN 1 ELSE 0 END) AS cart_cnt,
        SUM(CASE WHEN behavior = 'fav' THEN 1 ELSE 0 END) AS fav_cnt,
        SUM(CASE WHEN behavior = 'buy' THEN 1 ELSE 0 END) AS buy_cnt
    FROM default_catalog.default_database.kafka_source_user_behavior
    WHERE behavior IS NOT NULL
    GROUP BY 
        TUMBLE(ts_ltz, INTERVAL '10' MINUTE),
        category_id;

    # 任务 D (新增)：行为漏斗预聚合层 (DWS)
    INSERT INTO taobao_lake.db_ecommerce.dws_behavior_funnel
    SELECT 
        TUMBLE_START(ts_ltz, INTERVAL '10' MINUTE) AS win_start,
        TUMBLE_END(ts_ltz, INTERVAL '10' MINUTE) AS win_end,
        behavior,
        CASE behavior 
            WHEN 'pv' THEN '1-浏览(PV)' 
            WHEN 'fav' THEN '2-收藏(Fav)' 
            WHEN 'cart' THEN '3-加购(Cart)' 
            WHEN 'buy' THEN '4-购买(Buy)' 
        END AS step_name,
        COUNT(1) AS trigger_cnt
    FROM default_catalog.default_database.kafka_source_user_behavior
    WHERE behavior IN ('pv', 'cart', 'fav', 'buy')
    GROUP BY 
        TUMBLE(ts_ltz, INTERVAL '10' MINUTE),
        behavior;

END;

#小文件太多时：
#离线批处理
-- 进行 Iceberg 的底层文件合并机制
CALL taobao_lake.system.rewrite_data_files('db_ecommerce.ods_user_behavior');




