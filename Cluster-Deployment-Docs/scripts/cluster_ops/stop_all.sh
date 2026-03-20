#!/bin/bash

# =================================================================
# Description: 全栈大数据平台一键停止脚本 (Cluster Full-Stack Stopper)
# Principles: 后启动的组件先停止，保护元数据与任务状态
# =================================================================

echo "================ 正在按逆序安全停止全分布式集群 ================"

# 1. 停止数据治理中心：Atlas
echo ">>> 1. 停止 Apache Atlas"
ssh lake-master-01 "bash -lc '/opt/module/atlas-2.3.0/bin/atlas_stop.py'"

# 2. 停止计算引擎运行时：Flink & Spark
echo ">>> 2. 停止 Flink on YARN Session"
# 获取正在运行的 Flink 任务 ID 并执行 kill
flink_yarn_p=$(yarn application -list 2>/dev/null | grep "Apache Flink" | grep "RUNNING" | awk '{print $1}')
if [ -n "$flink_yarn_p" ]; then
    echo "正在终止 Flink 应用: $flink_yarn_p"
    yarn application -kill $flink_yarn_p
else
    echo "未检测到运行中的 Flink Session"
fi

echo ">>> 3. 停止 Spark History Server"
ssh lake-master-01 "bash -lc '/opt/module/spark-2.3.0/sbin/stop-history-server.sh'"

# 3. 停止数据仓库服务：Hive
echo ">>> 4. 停止 HiveServer2 & Metastore"
ssh lake-master-01 "ps -ef | grep hive | grep -E 'hiveserver2|metastore' | grep -v grep | awk '{print \$2}' | xargs kill -9 2>/dev/null"

# 4. 停止 NoSQL 与 索引引擎
echo ">>> 5. 停止 Solr Cloud"
ssh lake-master-01 "bash -lc '/opt/module/solr-8.11.2/bin/solr stop -all'"

echo ">>> 6. 停止 HBase 存储引擎"
ssh lake-master-01 "bash -lc 'stop-hbase.sh'"

# 5. 停止实时总线：Kafka
echo ">>> 7. 停止 Kafka 分布式集群"
ssh lake-master-01 "bash -lc '/opt/module/kafka-3.6.1/bin/kafka-server-stop.sh'"
ssh lake-worker-01 "bash -lc '/opt/module/kafka-3.6.1/bin/kafka-server-stop.sh'"
ssh lake-worker-02 "bash -lc '/opt/module/kafka-3.6.1/bin/kafka-server-stop.sh'"

# 6. 停止数据底座：Hadoop 核心
echo ">>> 8. 停止 JobHistoryServer"
ssh lake-master-01 "bash -lc 'mapred --daemon stop historyserver'"

echo ">>> 9. 停止 YARN 资源调度集群"
ssh lake-master-01 "bash -lc 'stop-yarn.sh'"

echo ">>> 10. 停止 HDFS 存储集群"
ssh lake-master-01 "bash -lc 'stop-dfs.sh'"

# 7. 停止协调基座：Zookeeper
echo ">>> 11. 停止 Zookeeper (3-Nodes Cluster)"
ssh lake-master-01 "bash -lc '/opt/module/zookeeper-3.7.1/bin/zkServer.sh stop'"
ssh lake-worker-01 "bash -lc '/opt/module/zookeeper-3.7.1/bin/zkServer.sh stop'"
ssh lake-worker-02 "bash -lc '/opt/module/zookeeper-3.7.1/bin/zkServer.sh stop'"

echo "=========================================================="
echo "    所有组件停止指令已执行完毕，请通过 jps_all.sh 确认"
echo "=========================================================="