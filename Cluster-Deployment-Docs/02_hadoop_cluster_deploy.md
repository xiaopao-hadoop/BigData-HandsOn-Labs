# 阶段二：Hadoop 3.1.3 集群部署 

Hadoop 是整个数据湖与实时计算平台的基础底座。后续的 HBase、Hive、Iceberg 均依赖 HDFS 作为底层存储，而 Spark 和 Flink 则依赖 YARN 进行统一的资源调度。本阶段部署稳定的 Hadoop 3.1.3 集群。

## 1. 目录初始化与权限分配

为了保证数据和运行环境的安全隔离，我们在阶段零规划了标准的目录结构。在 **3 台机器** 上分别执行以下命令，创建目录并移交权限给 `hadoop` 用户：

```bash
sudo mkdir -p /opt/software /opt/module /opt/logs /opt/data
sudo chown -R hadoop:hadoop /opt/software /opt/module /opt/logs /opt/data
可借助创建的xcall.sh脚本一键完成
```

## 2. 下载并解压 Hadoop 引擎包

切换到 `hadoop` 用户，并在 `lake-master-01` 节点上执行下载与解压操作：

```bash
cd /opt/software

# 使用 Apache Archive 链接下载官方 3.1.3 稳定版
wget [https://archive.apache.org/dist/hadoop/common/hadoop-3.1.3/hadoop-3.1.3.tar.gz](https://archive.apache.org/dist/hadoop/common/hadoop-3.1.3/hadoop-3.1.3.tar.gz)
tar -zxvf hadoop-3.1.3.tar.gz -C /opt/module/
```

## 3. 配置核心环境变量

在 `lake-master-01` 配置 Hadoop 的环境变量，并使其生效：

```bash
sudo nano /etc/profile.d/my_env.sh
```

追加以下 `HADOOP` 相关配置：

```bash
# HADOOP_HOME 声明
export HADOOP_HOME=/opt/module/hadoop-3.1.3
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
```

重载系统环境变量以立即生效：

```bash
source /etc/profile
```

## 4. 核心组件配置文件修改

进入 Hadoop 的配置目录：

```bash
cd /opt/module/hadoop-3.1.3/etc/hadoop/
```

### 4.1 核心通信路由 (`core-site.xml`)
此文件定义了 HDFS 的全局默认访问路径以及代理用户权限（为后续 Hive 和 Spark 提交任务做准备）。

```xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://lake-master-01:8020</value>
    </property>
    <property>
        <name>hadoop.tmp.dir</name>
        <value>/opt/data/hadoop/tmp</value>
    </property>
    <property>
        <name>hadoop.proxyuser.hadoop.hosts</name>
        <value>*</value>
    </property>
    <property>
        <name>hadoop.proxyuser.hadoop.groups</name>
        <value>*</value>
    </property>
</configuration>
```

### 4.2 存储元数据与副本策略 (`hdfs-site.xml`)
考虑到物理架构的规模约束（两台专门的 Worker 节点），将数据块的冗余副本数调整为 2，并指定 SecondaryNameNode 的辅助合并节点路由。

```xml
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>2</value>
    </property>
    <property>
        <name>dfs.namenode.secondary.http-address</name>
        <value>lake-worker-01:9868</value>
    </property>
</configuration>
```

### 4.3 资源调度与隔离机制 (`yarn-site.xml`)
声明 ResourceManager 的主控节点，并关闭虚拟内存硬性校验，提升微服务和虚拟化环境下的容器存活率。开启日志聚合功能以便后续的分布式任务排查。

```xml
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>lake-master-01</value>
    </property>
    <property>
        <name>yarn.nodemanager.vmem-check-enabled</name>
        <value>false</value>
    </property>
    <property>
        <name>yarn.log-aggregation-enable</name>
        <value>true</value>
    </property>
</configuration>
```

### 4.4 计算框架桥接 (`mapred-site.xml`)
指定 MapReduce 计算引擎的资源托管请求桥接至 YARN 框架。

```xml
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
</configuration>
```

### 4.5 节点拓扑注册 (`workers` 与 `hadoop-env.sh`)

编辑 `workers` 文件，声明全域数据节点清单：
```bash
nano workers
```
删除默认的 `localhost` 记录，写入集群的三个节点主机名：
```text
lake-master-01
lake-worker-01
lake-worker-02
```

> **避坑指南：**
> 严禁在 `workers` 文件中留下 `localhost`，并且每一行后不能有空格，文件末尾不能有空行，否则会导致 DataNode 启动异常或出现僵尸节点。

编辑 `hadoop-env.sh` 注入 JDK ：
```bash
# 在文件末尾追加，防止 SSH 非交互式登录引发的 JAVA_HOME 丢失
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
```

## 5. 全局跨节点分发

借助 `scp` 分发工具（或阶段一编写的批量工具）将配置完成的引擎目录与环境变量镜像同步至两台 Worker 节点：

```bash
# 物理下发 Hadoop 引擎目录
scp -r /opt/module/hadoop-3.1.3 hadoop@lake-worker-01:/opt/module/
scp -r /opt/module/hadoop-3.1.3 hadoop@lake-worker-02:/opt/module/

# 提权下发环境变量文件 (需要 root 权限写入配置区)
sudo scp /etc/profile.d/my_env.sh root@lake-worker-01:/etc/profile.d/
sudo scp /etc/profile.d/my_env.sh root@lake-worker-02:/etc/profile.d/
```

下发完毕后，在 Worker 节点上立即执行载入指令：
```bash
source /etc/profile
```

## 6. 存储格式化与集群点火

在首次挂载启动前，必须对底层文件系统进行结构建立。

> **⚠️ 注意：**
> NameNode 格式化指令具有破坏性，**仅允许在 `lake-master-01` 节点执行一次**，切勿重复执行！若多次执行将导致 ClusterID 变更，进而引发 DataNode 拒绝连接的灾难性故障。

```bash
# 1. 格式化 HDFS 元数据
hdfs namenode -format

# 2. 启动 HDFS 存储集群分层守护进程
start-dfs.sh

# 3. 启动 YARN 资源调度框架
start-yarn.sh
```

## 7. 阶段二验收验证

这是整个大数据平台启动的第一个核心服务，请务必经过以下严格的验证流程：

### 7.1 全局进程检查 (JPS)

在三台机器上分别输入 `jps`，核对进程分布是否符合我们的架构规划：

* **lake-master-01**: 必须包含 `NameNode`, `DataNode`, `ResourceManager`, `NodeManager`。
* **lake-worker-01**: 必须包含 `SecondaryNameNode`, `DataNode`, `NodeManager`。
* **lake-worker-02**: 必须包含 `DataNode`, `NodeManager`。

### 7.2 Web UI 健康度访问

* HDFS 分布式文件系统管理界面：`http://192.168.144.101:9870`
* YARN 分布式资源调度管理界面：`http://192.168.144.101:8088`

### 7.3 HDFS 读写冒烟测试

尝试向 HDFS 写入数据，验证 DataNode 的通信与权限：

```bash
hadoop fs -mkdir /test
hadoop fs -ls /
```
