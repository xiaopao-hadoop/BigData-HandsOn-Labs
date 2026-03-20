# 阶段四：流处理基座搭建

本阶段将为大数据平台引入实时流处理能力。将部署高吞吐的分布式消息队列 Kafka 作为数据缓冲，后续的Atlas也依赖于Kafka。并部署流批一体计算引擎 Flink（运行在 YARN 之上），打通从数据摄取到流处理的完整链路。

## 1. Kafka 3.6.1 分布式集群部署

Kafka 作为整个架构中的数据缓冲层与实时中枢，负责承接高并发的上游数据并为下游 Flink 提供稳定的数据流。

### 1.1 下载与解压
在 Master 节点 (`lake-master-01`) 执行：
```bash
cd /opt/software
# 下载 Kafka 3.6.1 (Scala 2.12 版本)
wget [https://archive.apache.org/dist/kafka/3.6.1/kafka_2.12-3.6.1.tgz](https://archive.apache.org/dist/kafka/3.6.1/kafka_2.12-3.6.1.tgz)

# 解压到安装目录并重命名
tar -zxvf kafka_2.12-3.6.1.tgz -C /opt/module/
mv /opt/module/kafka_2.12-3.6.1 /opt/module/kafka-3.6.1
```

### 1.2 修改核心配置 `server.properties`
编辑 Kafka 的核心配置文件：
```bash
nano /opt/module/kafka-3.6.1/config/server.properties
```
修改及追加以下参数（以 Master 节点为例的配置）：
```properties
# 1. Broker 的唯一标识，集群内每台机器必须不同
broker.id=0

# 2. 监听地址（绑定当前主机的名称）
listeners=PLAINTEXT://lake-master-01:9092
advertised.listeners=PLAINTEXT://lake-master-01:9092

# 3. 消息数据存储目录
log.dirs=/opt/data/kafka

# 4. 关联阶段三部署的 Zookeeper 集群
zookeeper.connect=lake-master-01:2181,lake-worker-01:2181,lake-worker-02:2181

# 5. 允许物理删除 Topic（强烈建议在测试/开发环境中开启）
delete.topic.enable=true

# 6. 设置默认分区数和副本数（契合我们 3 个 Broker 的集群规模）
num.partitions=3
offsets.topic.replication.factor=2
transaction.state.log.replication.factor=2
transaction.state.log.min.isr=2
```

### 1.3 分发 Kafka 并差异化配置节点
将配置好的 Kafka 分发到两台 Worker 节点：
```bash
scp -r /opt/module/kafka-3.6.1 hadoop@lake-worker-01:/opt/module/
scp -r /opt/module/kafka-3.6.1 hadoop@lake-worker-02:/opt/module/
```

**调整 Worker 01 配置** (`lake-worker-01`)：
```bash
nano /opt/module/kafka-3.6.1/config/server.properties
```
修改为：
```properties
broker.id=1
listeners=PLAINTEXT://lake-worker-01:9092
advertised.listeners=PLAINTEXT://lake-worker-01:9092
```

**调整 Worker 02 配置** (`lake-worker-02`)：
```bash
nano /opt/module/kafka-3.6.1/config/server.properties
```
修改为：
```properties
broker.id=2
listeners=PLAINTEXT://lake-worker-02:9092
advertised.listeners=PLAINTEXT://lake-worker-02:9092
```

### 1.4 创建目录与启动集群
三台机器均需创建数据和日志目录，利用批量脚本执行：
```bash
/home/hadoop/xcall.sh "mkdir -p /opt/data/kafka && mkdir -p /opt/logs/kafka"
```

为了统一日志管理规范，将 Kafka 运行日志重定向到 `/opt/logs/kafka`，并以后台方式启动整个集群：
```bash
# 设置日志输出目录环境变量并启动
/home/hadoop/xcall.sh 'export KAFKA_LOG4J_OPTS="-Dkafka.logs.dir=/opt/logs/kafka" && nohup /opt/module/kafka-3.6.1/bin/kafka-server-start.sh /opt/module/kafka-3.6.1/config/server.properties > /opt/logs/kafka/kafka-start.log 2>&1 &'
```

### 1.5 Kafka 集群功能验证 (冒烟测试)
创建测试 Topic：
```bash
/opt/module/kafka-3.6.1/bin/kafka-topics.sh --bootstrap-server lake-master-01:9092 --create --topic test-topic --partitions 3 --replication-factor 2
```
打开终端 A (启动消费者)：
```bash
/opt/module/kafka-3.6.1/bin/kafka-console-consumer.sh --bootstrap-server lake-master-01:9092 --topic test-topic
```
打开终端 B (启动生产者)：
```bash
/opt/module/kafka-3.6.1/bin/kafka-console-producer.sh --bootstrap-server lake-master-01:9092 --topic test-topic
```
> **💡 提示：**
> 在生产者终端输入任意字符串，若消费者终端能实时打印，则消息队列搭建成功。

---

## 2. Flink 1.17.2 部署 (Flink on YARN 架构)

为了实现资源的统一调度与隔离，我们将 Flink 部署在 YARN 模式下。Flink 负责从 Kafka 消费数据，进行实时 ETL 后写入下游（如 Iceberg 数据湖）。

### 2.1 下载与解压
在 `lake-master-01` 执行：
```bash
cd /opt/software
# 下载 Flink 1.17.2 (Scala 2.12 版本)
wget [https://archive.apache.org/dist/flink/flink-1.17.2/flink-1.17.2-bin-scala_2.12.tgz](https://archive.apache.org/dist/flink/flink-1.17.2/flink-1.17.2-bin-scala_2.12.tgz)
tar -zxvf flink-1.17.2-bin-scala_2.12.tgz -C /opt/module/
```

### 2.2 配置 Flink 与 Hadoop 交互环境变量
编辑环境变量配置：
```bash
sudo nano /etc/profile.d/my_env.sh
```
追加 Flink 配置，并强行绑定 Hadoop 依赖（这是 Flink on YARN 的关键）：
```bash
# FLINK_HOME
export FLINK_HOME=/opt/module/flink-1.17.2
export PATH=$PATH:$FLINK_HOME/bin

# 关键 1：让 Flink 能够找到 Hadoop 的配置体系
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop

# 关键 2：将 Hadoop 所有类路径传递给 Flink，直接挂载本地已有的 Hadoop 依赖
export HADOOP_CLASSPATH=`hadoop classpath`
```
分发并生效环境变量（参考阶段一工具）。

### 2.3 修改 Flink 核心配置 `flink-conf.yaml`
```bash
nano /opt/module/flink-1.17.2/conf/flink-conf.yaml
```
调整以下核心参数：
```yaml
# 指定 JobManager 地址
jobmanager.rpc.address: lake-master-01

# 内存配置微调（根据虚拟机资源进行适配）
jobmanager.memory.process.size: 1600m
taskmanager.memory.process.size: 2048m

# 每个 TaskManager 的插槽数（建议与 CPU 核心数一致或略小）
taskmanager.numberOfTaskSlots: 2

# 默认并行度
parallelism.default: 2

# === 容错与状态后端配置 (为 Flink 写入 Iceberg 做准备) ===
state.backend: hashmap
state.checkpoints.dir: hdfs://lake-master-01:8020/flink/checkpoints
state.savepoints.dir: hdfs://lake-master-01:8020/flink/savepoints

# 解决大数据生态中常见的类加载泄露冲突
classloader.check-leaked-classloader: false
```

### 2.4 流湖集成连接器 (Connectors)
Flink 操作 Iceberg 和 Kafka 需要额外的 Connector Jar 包：
```bash
cd /opt/module/flink-1.17.2/lib/

# 1. 下载 Iceberg Flink Runtime (1.4.3)
wget [https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-1.17/1.4.3/iceberg-flink-runtime-1.17-1.4.3.jar](https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-1.17/1.4.3/iceberg-flink-runtime-1.17-1.4.3.jar)

# 2. 下载 Flink SQL Connector Kafka
wget [https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/1.17.2/flink-sql-connector-kafka-1.17.2.jar](https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/1.17.2/flink-sql-connector-kafka-1.17.2.jar)
```

### 2.5 分发节点与集群验证
将 Flink 目录分发到 Worker 节点：
```bash
scp -r /opt/module/flink-1.17.2 hadoop@lake-worker-01:/opt/module/
scp -r /opt/module/flink-1.17.2 hadoop@lake-worker-02:/opt/module/
```

**验证 Flink on YARN 模式：**

1. 向 YARN 申请资源，开启一个常驻的 Flink Session 集群：
```bash
yarn-session.sh -nm flink-session -d -s 2 -jm 1024 -tm 2048
```
2. 访问 YARN Web UI (`http://192.168.144.101:8088`)，确认是否有一个名为 `flink-session` 的 Application 正在 `RUNNING`。
3. 进入 Flink SQL 交互式客户端验证计算引擎：
```bash
/opt/module/flink-1.17.2/bin/sql-client.sh embedded -s yarn-session
```
> **💡 提示：**
> 如果成功进入 `Flink SQL>` 命令行提示符，说明Flink已就绪！