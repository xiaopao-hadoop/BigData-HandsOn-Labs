#!/usr/bin/env bash
# ==============================================================================
# File: hbase-env.sh
# Description: HBase 环境变量与运行参数配置文件模板
# Usage:
#   1. 确认 <JAVA_HOME_PATH> 是否为你机器上真实的 JDK 路径 
#      (例如 /usr/lib/jvm/java-8-openjdk-amd64)
#   2. 如果你更改了全局目录规范，请同步修改 HBASE_LOG_DIR 的路径
#   3. 将此文件覆盖到 /opt/module/hbase-2.4.17/conf/hbase-env.sh
# ==============================================================================

# 指定 Java 运行环境路径
export JAVA_HOME=<JAVA_HOME_PATH>

# 核心：关闭 HBase 内置的 Zookeeper，使用外置的独立 ZK 集群
export HBASE_MANAGES_ZK=false

# 统一规范日志输出目录，方便后续采集
export HBASE_LOG_DIR=/opt/logs/hbase