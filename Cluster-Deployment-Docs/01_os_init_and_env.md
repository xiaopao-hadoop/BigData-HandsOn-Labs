# 阶段一：OS 初始化与基础环境构建

在大数据集群架构中，底层环境的稳定性直接决定了上层分布式组件的运行质量。本阶段涵盖主机网络配置、用户权限管理、SSH免密互信机制搭建，以及编程环境（JDK与Python）的部署。

---

## 1. 节点网络拓扑与主机名规划

分布式系统内部通信依赖 IP 进行通信。结合静态NAT模式，可进行IP和主机名的映射。在 Ubuntu环境下，执行以下配置。

### 1.1 主机名持久化配置
在各节点执行以下命令定义主机名：

```bash
# 在 Master 节点执行
sudo hostnamectl set-hostname lake-master-01

# 在 Worker 节点分别执行
# sudo hostnamectl set-hostname lake-worker-01
# sudo hostnamectl set-hostname lake-worker-02
```

### 1.2 Netplan 静态网络配置
编辑 Netplan 配置文件以映射集群 IP 地址，防止因 DHCP 变化导致集群通信中断：

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

写入以下标准配置（请根据实际物理网卡进行调整, via填写网卡的IP），以下以 `master` 节点举例：

```yaml
network:
  ethernets:
    ens33: 
      dhcp4: no
      addresses:
        - 192.168.144.101/24
      routes:
        - to: default
          via: 192.168.144.2
      nameservers:
        addresses: [192.168.144.2, 8.8.8.8]
  version: 2
```

应用配置使其生效：
```bash
sudo netplan apply
```

### 1.3 集群全域 Host 映射
编辑 `/etc/hosts`，确保三台机器的映射表保持绝对一致，供内部 RPC 调用：

```bash
sudo nano /etc/hosts
```

添加以下内容：
```text
192.168.1xx.101 lake-master-01
192.168.1xx.102 lake-worker-01
192.168.1xx.103 lake-worker-02
```

> **避坑指南：**
> 这里必须注释或删除 `127.0.1.1` 的本地解析项。若保留该项，部分大数据组件在注册服务时可能会错误抓取回环地址，导致跨节点通信失败（Connection Refused）。

---

## 2. 权限隔离与系统安全优化

基于最小权限原则，统一使用 `hadoop` 用户维护集群。

### 2.1 创建管理用户与 Sudo 免密配置
```bash
# 创建系统用户
sudo adduser hadoop

# 将用户加入 sudo 组
sudo usermod -aG sudo hadoop

# 配置 NOPASSWD 提权
sudo visudo
```

在文件末尾追加以下配置：
```text
hadoop ALL=(ALL) NOPASSWD:ALL
```

### 2.2 防火墙与时区同步
内网大数据集群为避免端口拦截问题，需统一关闭防火墙；同时校准所有节点时区以保证日志、任务调度的时间一致性：
```bash
# 关闭防火墙服务
sudo ufw disable

# 统一时区为 Asia/Shanghai
sudo timedatectl set-timezone Asia/Shanghai
```

### 2.3 SSH 互信机制构建 (Passwordless SSH)
在所有节点切换至 `hadoop` 用户，生成密钥对并建立 Master 对 Worker 的单向或双向信任：

```bash
# 在各节点生成 RSA 密钥对
ssh-keygen -t rsa  # 一路按回车即可

# 在 lake-master-01 上执行，将公钥分发至全集群
ssh-copy-id lake-master-01
ssh-copy-id lake-worker-01
ssh-copy-id lake-worker-02
```

---

## 3. 编程环境部署 (JDK & Python)

### 3.1 Java 环境安装
Hadoop 生态目前对 JDK 8 兼容性最好：

```bash
# 更新系统软件源
sudo apt update
# 安装OpenJDK 8
sudo apt install openjdk-8-jdk -y

# 验证安装结果
java -version

# 获取 JAVA_HOME 物理路径，记录备用
readlink -f $(which java)
```

### 3.2 Miniconda 与 Python 环境
为后续的数据分析及 Flink PyAlink 任务预置环境：

```bash
# 获取安装包
wget [https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh](https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh)

# 静默安装
bash Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda3
$HOME/miniconda3/bin/conda init bash
source ~/.bashrc

# 构建专用虚拟环境
conda create -n pyspider python=3.9 -y
conda activate pyspider
pip install kafka-python -i [https://pypi.tuna.tsinghua.edu.cn/simple](https://pypi.tuna.tsinghua.edu.cn/simple)
```

---

## 4. 集群运维自动化：xcall.sh 脚本

为实现“一处编写，处处同步”的高效运维，需部署批量指令执行脚本。

在 `/home/hadoop/` 路径下创建 [xcall](./Cluster-Deployment-Docs/scripts/tools/xcall.sh).sh：

```bash
#!/bin/bash

# 1. 参数校验
if [ $# -lt 1 ]; then
    echo "Usage: xcall <command>"
    exit 1
fi

# 2. 获取指令参数
CMD=$*

# 3. 遍历节点执行远程 SSH 指令
for host in lake-master-01 lake-worker-01 lake-worker-02
do
    echo "========== $host =========="
    # 登录 Shell 模式运行，确保环境变量加载
    ssh $host "bash -lc '$CMD'"
done
```

赋予执行权限并移至系统路径：
```bash
chmod +x xcall.sh
sudo mv xcall.sh /usr/local/bin/
```

为实现集群环境下的“单点修改，全局分发”，需部署跨节点文件同步脚本。

在 `/home/hadoop/` 路径下创建 [xsync](./Cluster-Deployment-Docs/scripts/tools/xsync.sh).sh：

```bash
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
```

赋予执行权限并移至系统路径（**优化建议**：在移动时顺便去掉 `.sh` 后缀，这样后续在任何目录下都可以直接敲击 `xsync` 而不需要带后缀）：
```bash
chmod +x xsync.sh
sudo mv xsync.sh /usr/local/bin/xsync
```

> **💡 提示：**
> **SSH 远程执行陷阱：** 默认 SSH 连接属于 `Non-interactive Shell`，不会加载 `~/.bashrc` 或 `/etc/profile`。通过在脚本中使用 `bash -lc` 参数，可以强制加载全量环境变量，有效避免 `Command not found` 或 `JAVA_HOME is not set` 等典型运维报错。

## 5. 阶段一验收验证

在正式进入 Hadoop 集群部署之前，请务必依次进行以下核心环境基线校验：

* **网络解析连通性**：三台机器是否都能互相 `ping` 通主机名（例如执行 `ping lake-worker-01`）？
* **Sudo 提权免密**：`hadoop` 用户是否可以无需输入密码直接执行 `sudo ls` 等管理员指令？
* **Java 运行版本**：执行 `java -version`，输出是否为预期的 `1.8` (OpenJDK 8) 版本？
* **SSH 免密通信**：Master 节点是否能无缝免密登录到两台 Worker 节点（例如执行 `ssh lake-worker-01` 可直接进入而无需验证密码）？