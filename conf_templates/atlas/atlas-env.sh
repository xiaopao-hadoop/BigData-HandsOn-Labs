#!/usr/bin/env bash
# ==============================================================================
# File: atlas-env.sh
# Description: Apache Atlas 环境变量与运行参数配置模板
# Usage:
#   1. 将 <JAVA_HOME_PATH> 替换为真实的 JDK 路径 
#   2. 如果更改了全局规范，请同步修改日志和 PID 的存放路径 (/opt/logs/atlas)
# ==============================================================================

# 指定 Java 运行环境路径
export JAVA_HOME=<JAVA_HOME_PATH>

# JVM 内存优化与日志输出规范配置 (按 Master 节点资源池分配)
export ATLAS_SERVER_OPTS="-Xms2g -Xmx2g -Datlas.logs.dir=/opt/logs/atlas"
export ATLAS_LOG_DIR=/opt/logs/atlas
export ATLAS_PID_DIR=/opt/logs/atlas

# ==================== 核心架构声明 ====================
# 明确告诉 Atlas：不要启动自带的单机版组件，使用我们外部署的分布式集群！
export MANAGE_LOCAL_HBASE=false
export MANAGE_LOCAL_SOLR=false
export MANAGE_EMBEDDED_CASSANDRA=false
export MANAGE_LOCAL_ELASTICSEARCH=false

# 桥接配置：告诉 Atlas 外部 HBase 的配置在哪里，从而顺藤摸瓜找到 HDFS 和 ZK
export HBASE_CONF_DIR=$HBASE_HOME/conf