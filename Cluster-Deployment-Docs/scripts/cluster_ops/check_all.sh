#!/bin/bash

# =================================================================
# Description: 全栈大数据平台健康自检脚本 (Cluster Health Dashboard)
# Usage: ./check_all.sh
# =================================================================

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' 

# --- 集群配置定义 ---
MASTER="lake-master-01"
WORKER1="lake-worker-01"
WORKER2="lake-worker-02"
ALL_NODES=($MASTER $WORKER1 $WORKER2)
MASTER_IP="192.168.144.101"

echo "==================== 集群健康状态全面自检 ===================="

# 1. 检查 Zookeeper (3.7.1)
echo -e "\n[1. Zookeeper Cluster Status]"
for i in "${ALL_NODES[@]}"
do
    status=$(ssh $i "bash -lc '/opt/module/zookeeper-3.7.1/bin/zkServer.sh status 2>&1'")
    if [[ $status == *"Mode"* ]]; then
        mode=$(echo $status | grep -oP 'Mode: \K\w+')
        echo -e "$i: ${GREEN}RUNNING${NC} ($mode)"
    else
        echo -e "$i: ${RED}STOPPED${NC}"
    fi
done

# 2. 检查 HDFS (3.1.3)
echo -e "\n[2. HDFS Infrastructure]"
nn_p=$(ssh $MASTER "bash -lc 'jps | grep NameNode'")
if [ -n "$nn_p" ]; then
    echo -e "NameNode: ${GREEN}ACTIVE${NC}"
    echo -e "Web UI:   http://${MASTER_IP}:9870"
else
    echo -e "NameNode: ${RED}OFFLINE${NC}"
fi

# 3. 检查 YARN
echo -e "\n[3. YARN Resource Manager]"
rm_p=$(ssh $MASTER "bash -lc 'jps | grep ResourceManager'")
if [ -n "$rm_p" ]; then
    echo -e "RM Status: ${GREEN}ACTIVE${NC}"
    echo -e "Web UI:    http://${MASTER_IP}:8088"
else
    echo -e "RM Status: ${RED}OFFLINE${NC}"
fi

# 4. 检查 Kafka (3.6.1)
echo -e "\n[4. Kafka Message Bus]"
for i in "${ALL_NODES[@]}"
do
    kf_p=$(ssh $i "bash -lc 'jps | grep Kafka'")
    if [ -n "$kf_p" ]; then
        echo -e "$i: ${GREEN}RUNNING${NC}"
    else
        echo -e "$i: ${RED}STOPPED${NC}"
    fi
done

# 5. 检查 HBase (2.4.17)
echo -e "\n[5. HBase Storage]"
hb_p=$(ssh $MASTER "bash -lc 'jps | grep HMaster'")
if [ -n "$hb_p" ]; then
    echo -e "HMaster:  ${GREEN}ACTIVE${NC}"
    echo -e "Web UI:   http://${MASTER_IP}:16010"
else
    echo -e "HMaster:  ${RED}OFFLINE${NC}"
fi

# 6. 检查 Solr (8.11.2)
echo -e "\n[6. Solr Cloud Search]"
if (echo > /dev/tcp/${MASTER_IP}/8983) >/dev/null 2>&1; then
    echo -e "Solr Node: ${GREEN}ONLINE${NC} (Port 8983 Active)"
    echo -e "Web UI:    http://${MASTER_IP}:8983"
else
    echo -e "Solr Node: ${RED}OFFLINE${NC}"
fi

# 7. 检查 Hive (3.1.3)
echo -e "\n[7. Hive Data Warehouse]"
h_ms=$(ssh $MASTER "bash -lc 'ps -ef | grep hive | grep metastore | grep -v grep'")
if [ -n "$h_ms" ]; then
    echo -e "Metastore: ${GREEN}ONLINE${NC}"
else
    echo -e "Metastore: ${RED}OFFLINE${NC}"
fi

h_hs2=$(ssh $MASTER "bash -lc 'netstat -tunlp | grep 10000'")
if [ -n "$h_hs2" ]; then
    echo -e "HS2:       ${GREEN}RUNNING${NC} (Port 10000)"
    echo -e "JDBC URL:  ${GREEN}beeline -u jdbc:hive2://${MASTER}:10000 -n hadoop${NC}"
else
    echo -e "HS2:       ${RED}OFFLINE${NC}"
fi

# 8. 检查 Spark History
echo -e "\n[8. Spark Engine History]"
sh_p=$(ssh $MASTER "bash -lc 'jps -l | grep org.apache.spark.deploy.history.HistoryServer'")
if [ -n "$sh_p" ]; then
    echo -e "History:   ${GREEN}RUNNING${NC}"
    echo -e "Web UI:    http://${MASTER_IP}:18080"
else
    echo -e "History:   ${RED}OFFLINE${NC}"
fi

# 9. 检查 Flink (1.17.2)
echo -e "\n[9. Flink on YARN Runtime]"
flink_yarn_p=$(yarn application -list 2>/dev/null | grep "Apache Flink" | grep "RUNNING")
if [ -n "$flink_yarn_p" ]; then
    app_id=$(echo $flink_yarn_p | awk '{print $1}')
    echo -e "Session:   ${GREEN}ACTIVE${NC} (AppID: $app_id)"
    echo -e "SQL Client: ${GREEN}sql-client.sh embedded -s yarn-session${NC}"
else
    echo -e "Session:   ${RED}INACTIVE${NC}"
fi

# 10. 检查 Apache Atlas (2.3.0)
echo -e "\n[10. Data Governance - Atlas]"
atlas_p=$(ssh $MASTER "bash -lc 'netstat -tunlp | grep 21000'")
if [ -n "$atlas_p" ]; then
    echo -e "Atlas:     ${GREEN}READY${NC}"
    echo -e "Web UI:    http://${MASTER_IP}:21000"
else
    echo -e "Atlas:     ${RED}NOT READY${NC} (Initializing or Offline)"
fi

echo -e "\n==================== 自检工作结束 ===================="