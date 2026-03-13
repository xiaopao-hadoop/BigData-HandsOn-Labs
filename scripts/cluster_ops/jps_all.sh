#!/bin/bash

# =================================================================
# Description: 全集群 Java 进程一键巡检脚本 (Global JPS Inspector)
# Usage: ./jps_all.sh
# =================================================================

# 循环遍历集群所有节点
for host in lake-master-01 lake-worker-01 lake-worker-02
do
    echo "------------------- $host -------------------"
    # 执行远程 jps 命令
    # 使用 -l 参数显示完整的类名
    ssh $host "bash -lc 'jps -l'"
done