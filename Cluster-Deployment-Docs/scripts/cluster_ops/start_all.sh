#!/bin/bash

# =================================================================
# Description: 集群组件一键启动脚本 (Cluster Full-Stack Starter)
# Dependencies: ZK -> Hadoop -> Kafka -> NoSQL -> Hive -> Governance
# =================================================================

# 获取当前日期用于日志标记
DATE=$(date +%Y%m%d%H%M)

echo "================ 正在按顺序启动全分布式集群 ================"

# 1. 启动 Zookeeper (基座)
echo "--- 1. 启动 Zookeeper (3台) ---"
for i in lake-master-01 lake-worker-01 lake-worker-02
do
    ssh $i "/opt/module/zookeeper-3.7.1/bin/zkServer.sh start"
done
sleep 2

# 2. 启动 Hadoop 核心
echo "--- 2. 启动 HDFS ---"
ssh lake-master-01 "start-dfs.sh"

echo "--- 3. 启动 YARN ---"
ssh lake-master-01 "start-yarn.sh"

echo "--- 4. 启动 MapReduce 历史服务器 ---"
ssh lake-master-01 "mapred --daemon start historyserver"

# 3. 启动 消息队列 Kafka
echo "--- 5. 启动 Kafka (3台) ---"
for i in lake-master-01 lake-worker-01 lake-worker-02
do
    ssh $i "export KAFKA_LOG4J_OPTS='-Dkafka.logs.dir=/opt/logs/kafka'; nohup /opt/module/kafka-3.6.1/bin/kafka-server-start.sh -daemon /opt/module/kafka-3.6.1/config/server.properties >/dev/null 2>&1 &"
done

# 4. 启动 NoSQL 存储与索引
echo "--- 6. 启动 HBase ---"
ssh lake-master-01 "start-hbase.sh"

echo "--- 7. 启动 Solr (Cloud模式) ---"
#ssh lake-master-01 "/opt/module/solr/bin/solr start -cloud -s /opt/module/solr/server/solr -z lake-master-01:2181,lake-worker-01:2181,lake-worker-02:2181/solr -force"



# 5. 启动 Hive 相关服务
echo "--- 8. 启动 Hive Metastore ---"
ssh lake-master-01 "nohup hive --service metastore >> /opt/logs/hive/metastore.log 2>&1 &"

echo "--- 9. 启动 HiveServer2 (用于 JDBC/Beeline 连接) ---"
ssh lake-master-01 "nohup hive --service hiveserver2 >> /opt/logs/hive/hiveserver2.log 2>&1 &"

# 6. 启动 Spark/Flink 运行时
echo "--- 10. 启动 Spark History Server ---"
ssh lake-master-01 "/opt/module/spark-2.3.0/sbin/start-history-server.sh"

# 7. 启动 Atlas (最后启动，依赖以上所有组件)
echo "--- 12. 启动 Apache Atlas (初始化约需 1-2 分钟) ---"
#ssh lake-master-01 "python3 /opt/module/atlas-2.3.0/bin/atlas_start.py"

# 8.启动starrocks
echo "--- 12.启动 Starrocks ---"
#ssh lake-master-01 "/home/hadoop/xcall.sh sudo sysctl -w vm.max_map_count=262144"
#ssh lake-master-01 "/opt/module/starrocks-3.2.16/fe/bin/start_fe.sh --daemon"
#ssh lake-worker-01 "/opt/module/starrocks-3.2.16/be/bin/start_be.sh --daemon"
#ssh lake-worker-02 "/opt/module/starrocks-3.2.16/be/bin/start_be.sh --daemon"


echo "=========================================================="
echo "    所有组件启动指令已发出，请使用 xcall.sh jps 确认状态"
echo "    HiveServer2 和 Atlas 启动较慢，请稍后访问 UI 界面"
echo "=========================================================="
