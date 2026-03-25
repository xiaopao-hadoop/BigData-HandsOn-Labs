# 扩大最大内存映射区域数量，避免启动失败
sudo sysctl -w vm.max_map_count=262144

# 启动StarRocks
#master：
cd /opt/module/starrocks-3.2.16/fe
./bin/start_fe.sh --daemon
#worker：
cd /opt/module/starrocks-3.2.16/be
./bin/start_be.sh --daemon

#进入客户端（这里StarRocks兼容MySQL协议，直接通过mysql进行sql交互命令行）
mysql -h lake-master-01 -P 9030 -u root

#注册be
ALTER SYSTEM ADD BACKEND "lake-worker-01:9050";
ALTER SYSTEM ADD BACKEND "lake-worker-02:9050";

#检查集群
SHOW PROC '/backends'\G # 确保alive都是true


# 创建名为 taobao_lake 的外部 Catalog
CREATE EXTERNAL CATALOG taobao_lake
PROPERTIES (
    "type"="iceberg",
    "iceberg.catalog.type"="hive",
    "hive.metastore.uris"="thrift://lake-master-01:9083" 
);

# 测试一下是否挂载成功
SHOW DATABASES FROM taobao_lake;

#在 StarRocks 创建本地维度表 
#这里是商品品类和真实名字的对照表：需要插入数据，具体的对照看这里：TaoBao-UserBehavior-Analysis\INSERT_INTO_dim_category_VALUES.sql
CREATE DATABASE IF NOT EXISTS sr_ecommerce;
USE sr_ecommerce;
CREATE TABLE dim_category (
    category_id STRING,
    category_name STRING
) 
ENGINE=OLAP
PRIMARY KEY(category_id)
DISTRIBUTED BY HASH(category_id) BUCKETS 1
#指定副本数为 2（匹配 2 个 BE 节点）
PROPERTIES (
    "replication_num" = "2"
);

#跨源 OLAP 查询以及创建视图方便后面BI工具查询:
#mysql>
USE sr_ecommerce;

# 1. 建品类指标视图 
DROP VIEW IF EXISTS view_category_metrics;
CREATE VIEW view_category_metrics AS
SELECT 
    d.category_name AS category_name,
    SUM(m.pv_cnt) AS total_pv,
    SUM(m.cart_cnt) AS total_cart,
    SUM(m.fav_cnt) AS total_fav,
    SUM(m.buy_cnt) AS total_buy
FROM taobao_lake.db_ecommerce.dws_category_metrics m
JOIN sr_ecommerce.dim_category d 
  ON m.category_id = d.category_id
GROUP BY d.category_name;

# 2. 建好漏斗视图 
DROP VIEW IF EXISTS view_behavior_funnel;
CREATE VIEW view_behavior_funnel AS
SELECT 
    step_name AS step_name,
    SUM(trigger_cnt) AS trigger_cnt
FROM taobao_lake.db_ecommerce.dws_behavior_funnel
GROUP BY step_name;