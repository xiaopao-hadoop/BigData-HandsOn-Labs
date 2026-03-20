#!/bin/bash
# =================================================================
# Description: 集群命令批量执行脚本 (Cluster Command Executor)
# Usage: ./xcall.sh <command>
# =================================================================
# 1. 参数校验
if [ $# -lt 1 ]; then
    echo "Usage: xcall <command>"
    exit 1
fi
# 2. 获取指令参数
CMD=$*
# 3. 遍历节点进行远程 SSH 连接和执行 CMD 指令
for host in lake-master-01 lake-worker-01 lake-worker-02
do
    echo "========== $host =========="
    # 以登录 Shell 模式运行，确保环境变量加载
    ssh $host "bash -lc '$CMD'"
done