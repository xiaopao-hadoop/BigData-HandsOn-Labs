# ==============================================================================
# File: my_env.sh
# Description: 大数据集群全局环境变量配置模板
# Usage: 
#   1. 根据你的实际安装路径 (默认规划为 /opt/module) 和组件版本核对以下变量
#   2. 如果你的组件安装在其他路径，请全局替换 /opt/module 为你的 <INSTALL_BASE_DIR>
#   3. 将此文件分发至所有集群节点的 /etc/profile.d/ 目录下 (需 sudo 权限)
#   4. 在所有节点执行 `source /etc/profile` 使其全局生效
# ==============================================================================

# ==================== [ 1. 数据底座 (Hadoop 生态) ] ====================
export HADOOP_HOME=/opt/module/hadoop-3.1.3
export HADOOP_MAPRED_HOME=$HADOOP_HOME
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin

# ==================== [ 2. 协调与消息基座 (ZK & Kafka) ] ====================
export ZOOKEEPER_HOME=/opt/module/zookeeper-3.7.1
export PATH=$PATH:$ZOOKEEPER_HOME/bin

export KAFKA_HOME=/opt/module/kafka-3.6.1
export PATH=$PATH:$KAFKA_HOME/bin

# ==================== [ 3. NoSQL 与 搜索引擎 (HBase & Solr) ] ====================
export HBASE_HOME=/opt/module/hbase-2.4.17
export PATH=$PATH:$HBASE_HOME/bin

# 注意核实 Solr 的目录名称是否带版本号
export SOLR_HOME=/opt/module/solr
export PATH=$PATH:$SOLR_HOME/bin

# ==================== [ 4. 数据仓库与计算引擎 (Hive, Spark, Flink) ] ====================
export HIVE_HOME=/opt/module/hive-3.1.3
export PATH=$PATH:$HIVE_HOME/bin

export SPARK_HOME=/opt/module/spark-2.3.0
export PATH=$PATH:$SPARK_HOME/bin

export FLINK_HOME=/opt/module/flink-1.17.2
export PATH=$PATH:$FLINK_HOME/bin

# --- 流湖集成核心桥接配置 (Flink on YARN) ---
# 让 Flink 能够找到 Hadoop 的配置体系，以便将 Checkpoint 写入 HDFS
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
# 将 Hadoop 所有类路径一次性传递给 Flink，避免提交任务时找不到类库
export HADOOP_CLASSPATH=`hadoop classpath`
