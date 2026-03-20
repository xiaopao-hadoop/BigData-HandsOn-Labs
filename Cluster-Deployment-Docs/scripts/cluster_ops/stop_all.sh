#!/bin/bash

# =================================================================
# Description: 集群组件一键停止脚本 (Cluster Full-Stack Stopper)
# Principles: 后启动的组件先停止，保护元数据与任务状态
# =================================================================


echo "================ 正在按顺序停止集群 ================"
echo "--- 0. 停止 Starrocks ---"
ssh lake-master-01 "/opt/module/starrocks-3.2.16/fe/bin/stop_fe.sh"
ssh lake-worker-01 "/opt/module/starrocks-3.2.16/be/bin/stop_be.sh"
ssh lake-worker-02 "/opt/module/starrocks-3.2.16/be/bin/stop_be.sh"h


# 1. 停止 Apache Atlas (最先停止，确保元数据不再写入)
echo "--- 1. 停止 Apache Atlas ---"
ssh lake-master-01 "python3 /opt/module/atlas-2.3.0/bin/atlas_stop.py"

# 2. 停止 Flink (清理 YARN 上的 Session)
echo "--- 2. 停止 Flink on YARN ---"
flink_yarn_p=$(yarn application -list 2>/dev/null | grep "Apache Flink" | grep "RUNNING" | awk '{print $1}')
if [ -n "$flink_yarn_p" ]; then
    echo "正在终止 Flink 应用: $flink_yarn_p"
    yarn application -kill $flink_yarn_p
else
    echo "Flink Session 未运行。"
fi

# 3. 停止 Hive 相关服务
echo "--- 3. 停止 HiveServer2 ---"
ssh lake-master-01 "ps -ef | grep hive | grep hiveserver2 | grep -v grep | awk '{print \$2}' | xargs kill -9 2>/dev/null"

echo "--- 4. 停止 Hive Metastore ---"
ssh lake-master-01 "ps -ef | grep hive | grep metastore | grep -v grep | awk '{print \$2}' | xargs kill -9 2>/dev/null"

# 4. 停止 Spark 运行时
echo "--- 5. 停止 Spark History Server ---"
ssh lake-master-01 "/opt/module/spark-2.3.0/sbin/stop-history-server.sh"

# 5. 停止 搜索引擎与 NoSQL 存储
echo "--- 6. 停止 Solr (Cloud Mode) ---"
ssh lake-master-01 "/opt/module/solr-8.11.2/bin/solr stop -all"

echo "--- 7. 停止 HBase ---"
ssh lake-master-01 "stop-hbase.sh"

# 6. 停止 消息队列 Kafka
echo "--- 8. 停止 Kafka (3台) ---"
for i in lake-master-01 lake-worker-01 lake-worker-02
do
    ssh $i "/opt/module/kafka-3.6.1/bin/kafka-server-stop.sh"
done

# 7. 停止 Hadoop 核心组件
echo "--- 9. 停止 Hadoop MapReduce 历史服务器 ---"
ssh lake-master-01 "mapred --daemon stop historyserver"

echo "--- 10. 停止 Hadoop YARN ---"
ssh lake-master-01 "stop-yarn.sh"

echo "--- 11. 停止 Hadoop HDFS ---"
"stop-dfs.sh"

# 8. 停止 Zookeeper (最后停止)
echo "--- 12. 停止 Zookeeper (3台) ---"
 /home/hadoop/xcall.sh "/opt/module/zookeeper-3.7.1/bin/zkServer.sh stop"


echo "==================== 全集群停止完毕 ===================="