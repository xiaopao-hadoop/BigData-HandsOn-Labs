#!/bin/bash

# =================================================================
# Description: 集群文件同步脚本 (Cluster File Synchronizer)
# Usage: ./xsync.sh /path/to/file_or_dir
# =================================================================

# 1. 检查参数是否为空
if [ $# -lt 1 ]; then
    echo "Usage: xsync <file/dir>"
    exit 1
fi

# 2. 遍历集群节点 
for host in lake-worker-01 lake-worker-02
do
    echo "------------------- Synchronizing to $host -------------------"
    # 遍历所有待同步的文件或目录
    for file in $@
    do
        # 3. 判断路径是否存在
        if [ -e $file ]; then
            # 获取父目录绝对路径
            pdir=$(cd -P $(dirname $file); pwd)
            # 获取当前文件名称
            fname=$(basename $file)
            # 在目标节点创建对应目录并同步文件
            ssh $host "mkdir -p $pdir"
            rsync -av $pdir/$fname $host:$pdir
        else
            echo "$file does not exist!"
        fi
    done
done