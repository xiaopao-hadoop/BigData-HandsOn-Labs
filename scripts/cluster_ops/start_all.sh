#!/bin/bash

# =================================================================
# Description: 全栈大数据平台一键启动脚本 (Cluster Full-Stack Starter)
# Dependencies: ZK -> Hadoop -> Kafka -> NoSQL -> Hive -> Governance
# =================================================================

echo "================ 正在按依赖拓扑启动全分布式集群 ================"

# 1. 启动协调基座：Zookeeper
echo ">>> 1. 启动 Zookeeper (3-Nodes Cluster)"
# 调用 xcall 执行批量启动
ssh lake-master-01 "bash -lc '/opt/module/zookeeper-3.7.1/bin/zkServer.sh start'"
ssh lake-worker-01 "bash -lc '/opt/module/zookeeper-3.7.1/bin/zkServer.sh start'"
ssh lake-worker-02 "bash -lc '/opt/module/zookeeper-3.7.1/bin/zkServer.sh start'"
sleep 2

# 2. 启动数据底座：Hadoop 核心
echo ">>> 2. 启动 HDFS 存储集群"
ssh lake-master-01 "bash -lc 'start-dfs.sh'"

echo ">>> 3. 启动 YARN 资源调度集群"
ssh lake-master-01 "bash -lc 'start-yarn.sh'"

echo ">>> 4. 启动 JobHistoryServer"
ssh lake-master-01 "bash -lc 'mapred --daemon start historyserver'"

# 3. 启动实时总线：Kafka
echo ">>> 5. 启动 Kafka 分布式集群"
ssh lake-master-01 "bash -lc 'export KAFKA_LOG4J_OPTS=\"-Dkafka.logs.dir=/opt/logs/kafka\"; nohup /opt/module/kafka-3.6.1/bin/kafka-server-start.sh -daemon /opt/module/kafka-3.6.1/config/server.properties >/dev/null 2>&1 &'"
ssh lake-worker-01 "bash -lc 'export KAFKA_LOG4J_OPTS=\"-Dkafka.logs.dir=/opt/logs/kafka\"; nohup /opt/module/kafka-3.6.1/bin/kafka-server-start.sh -daemon /opt/module/kafka-3.6.1/config/server.properties >/dev/null 2>&1 &'"
ssh lake-worker-02 "bash -lc 'export KAFKA_LOG4J_OPTS=\"-Dkafka.logs.dir=/opt/logs/kafka\"; nohup /opt/module/kafka-3.6.1/bin/kafka-server-start.sh -daemon /opt/module/kafka-3.6.1/config/server.properties >/dev/null 2>&1 &'"

# 4. 启动 NoSQL 与 索引引擎
echo ">>> 6. 启动 HBase 存储引擎"
ssh lake-master-01 "bash -lc 'start-hbase.sh'"

echo ">>> 7. 启动 Solr Cloud (Atlas 索引后端)"
ssh lake-master-01 "bash -lc '/opt/module/solr-8.11.2/bin/solr start -cloud -z lake-master-01:2181,lake-worker-01:2181,lake-worker-02:2181 -p 8983 -force'"

# 5. 启动数据仓库服务：Hive
echo ">>> 8. 启动 Hive Metastore"
ssh lake-master-01 "bash -lc 'nohup hive --service metastore >> /opt/logs/hive/metastore.log 2>&1 &'"

echo ">>> 9. 启动 HiveServer2"
ssh lake-master-01 "bash -lc 'nohup hive --service hiveserver2 >> /opt/logs/hive/hiveserver2.log 2>&1 &'"

# 6. 启动计算引擎运行时：Spark & Flink
echo ">>> 10. 启动 Spark History Server"
ssh lake-master-01 "bash -lc '/opt/module/spark-2.3.0/sbin/start-history-server.sh'"

echo ">>> 11. 启动 Flink YARN Session"
ssh lake-master-01 "bash -lc 'yarn-session.sh -nm flink-session -d -s 2 -jm 1024 -tm 2048'"

# 7. 启动数据治理中心：Atlas
echo ">>> 12. 启动 Apache Atlas (此组件加载较慢)"
ssh lake-master-01 "bash -lc '/opt/module/atlas-2.3.0/bin/atlas_start.py'"

echo "=========================================================="
echo "    所有组件启动指令已发出，请使用 jps_all.sh 确认状态"
echo "=========================================================="