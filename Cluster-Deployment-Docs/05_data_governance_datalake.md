# 阶段五：数据治理与数据湖集成

在大数据企业级落地中，单纯的计算与存储集群仅构成了物理骨架，而数据治理才更加体现数据资产。本阶段将为数据治理注入“灵魂”：部署 Apache Atlas 建立全局数据血缘（Data Lineage）与元数据管理体系，并引入 Apache Iceberg 构建新一代流批一体的数据湖底座，彻底打通由 Kafka 到 Flink 再到数据湖的实时分析链路。

---

## 1. Apache Atlas 2.3.0 部署指南 (元数据与血缘治理)


Atlas 的运行深度依赖于我们在前置阶段部署的基础组件：HBase 提供图数据库（JanusGraph）底层存储，Solr 提供全文索引，Kafka 提供实时消息驱动与通知，Zookeeper 提供高可用协调。

### 1.1 目录准备与引擎包部署
在 Master 节点 (`lake-master-01`) 执行解压与规范化重命名：

```bash
cd /opt/software
# 解压到安装目录并重命名
tar -zxvf apache-atlas-2.3.0-bin.tar.gz -C /opt/module/
mv /opt/module/apache-atlas-2.3.0 /opt/module/atlas-2.3.0
```

### 1.2 核心应用配置 (`atlas-application.properties`)
该配置文件是 Atlas 的神经中枢，决定了它如何与底层生态组件握手交互。

```bash
nano /opt/module/atlas-2.3.0/conf/atlas-application.properties
```

修改并核对以下核心配置：

```properties
# -------- 1. HBase 存储后端配置 (Graph Storage) --------
atlas.graph.storage.backend=hbase2
# 复用全局 ZK 集群
atlas.graph.storage.hostname=lake-master-01:2181,lake-worker-01:2181,lake-worker-02:2181
# Atlas 在 HBase 中自动创建的底层系统表名
atlas.graph.storage.hbase.table=apache_atlas_janus

# -------- 2. Solr 索引后端配置 (Graph Index) --------
atlas.graph.index.search.backend=solr
atlas.graph.index.search.solr.mode=cloud
# 关联 ZK 集群以实现 SolrCloud 服务发现
atlas.graph.index.search.solr.zookeeper-url=lake-master-01:2181,lake-worker-01:2181,lake-worker-02:2181

# -------- 3. Kafka 通知机制配置 (Notification) --------
atlas.notification.embedded=false
atlas.kafka.bootstrap.servers=lake-master-01:9092,lake-worker-01:9092,lake-worker-02:9092
atlas.kafka.zookeeper.connect=lake-master-01:2181,lake-worker-01:2181,lake-worker-02:2181

# -------- 4. Atlas 身份验证 (生产环境建议接入 LDAP/Kerberos) --------
atlas.authentication.method.kerberos=false
atlas.authentication.method.file=true
atlas.authentication.method.file.filename=users-credentials.properties

# -------- 5. Atlas Server 基础路由配置 --------
atlas.rest.address=http://lake-master-01:21000
```

### 1.3 运行环境与内存调优 (`atlas-env.sh`)

```bash
nano /opt/module/atlas-2.3.0/conf/atlas-env.sh
```

注入 JVM 堆内存优化参数并指定外部依赖配置路径：

```bash
# 指定 JDK 路径
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

# 内存优化：根据 Master 节点资源池分配内存（不少于2GB），并指定规范的日志输出目录
export ATLAS_SERVER_OPTS="-Xms2g -Xmx2g -Datlas.logs.dir=/opt/logs/atlas"
export ATLAS_LOG_DIR=/opt/logs/atlas
export ATLAS_PID_DIR=/opt/logs/atlas

# 核心关联：显式声明 HBase 配置文件位置，供 Atlas 客户端加载
export HBASE_CONF_DIR=$HBASE_HOME/conf
```

### 1.4 预建 Solr 索引库 (关键前置)

> **避坑指南：**
> Atlas 首次运行前，**必须手动**在 SolrCloud 中创建其依赖的 Collection，否则 Atlas 服务进程会因为找不到索引库而直接崩溃（Crash Loop）。Atlas 源码包中自带了这部分初始化模板。

进入 Solr `bin` 目录执行 Collection 初始化：

```bash
cd /opt/module/solr-8.11.2/bin

# 使用 Atlas 自带的配置文件创建 3 个核心 Collection
./solr create -c vertex_index -d /opt/module/atlas-2.3.0/conf/solr -shards 3 -replicationFactor 2 -force
./solr create -c edge_index -d /opt/module/atlas-2.3.0/conf/solr -shards 3 -replicationFactor 2 -force
./solr create -c fulltext_index -d /opt/module/atlas-2.3.0/conf/solr -shards 3 -replicationFactor 2 -force
```

### 1.5 启动 Atlas Server

```bash
# 预建日志目录以防权限报错
mkdir -p /opt/logs/atlas

# 以后台进程启动 Atlas Server
/opt/module/atlas-2.3.0/bin/atlas_start.py
```
> **提示：**
> 启动完成后，约需等待 1-2 分钟（等待各类图实例初始化），随后可通过 `http://192.168.144.101:21000` 访问 Web 控制台。系统默认的超级管理员账号与密码均为 `admin`。

---

## 2. 注入 Hive Hook (自动化数据血缘采集)

为了让 Atlas 能够自动捕捉 Hive 数仓的 DDL（建表/改表）与 DML（插入/覆盖）操作并动态生成血缘图（Data Lineage），必须将 Atlas 的钩子组件（Hook：类似监控的作用）放到到 Hive 的执行生命周期中。

### 2.1 部署 Hook 依赖包
将 Atlas 编译打包好的 Hook 库硬链接或复制至 Hive 的运行环境库目录：

```bash
cp -r /opt/module/atlas-2.3.0/hook/hive/* /opt/module/hive-3.1.3/lib/
```

### 2.2 开启 Hive 事件监听钩子
编辑 Hive 核心配置文件：

```bash
nano /opt/module/hive-3.1.3/conf/hive-site.xml
```

追加以下生命周期事件钩子配置：

```xml
<property>
    <name>hive.exec.post.hooks</name>
    <value>org.apache.atlas.hive.hook.HiveHook</value>
</property>
```

### 2.3 同步 Atlas 通信配置
将 Atlas 的配置文件下发给 Hive，使 Hive 能够明确如何通过 Kafka 代理将捕获到的血缘事件推送给 Atlas 服务端：

```bash
cp /opt/module/atlas-2.3.0/conf/atlas-application.properties /opt/module/hive-3.1.3/conf/
```

---

## 3. 部署 Apache Iceberg (流批一体数据湖底座)

Iceberg 是一种企业级的高性能开放数据湖表格式（Table Format）。它完美契合 Flink 的毫秒级流式写入与 Hive/Spark 的高并发批式查询，是构建“湖仓一体”（Lakehouse）架构的基座。

### 3.1 Flink 实时入湖环境配置 (Streaming Ingestion)
进入阶段四部署的 Flink 库目录，拉取 Iceberg 运行时依赖及 Hive Catalog 桥接器：

```bash
cd /opt/module/flink-1.17.2/lib/

# 获取 Flink-Iceberg 核心连接器包 (适配 Flink 1.17 跨版本)
wget [https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-1.17/1.4.3/iceberg-flink-runtime-1.17-1.4.3.jar](https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-1.17/1.4.3/iceberg-flink-runtime-1.17-1.4.3.jar)

# 获取 Flink-Hive 桥接连接器 (Iceberg 依赖 Hive Metastore 进行全局目录管理)
wget [https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-hive-3.1.3_2.12/1.17.2/flink-sql-connector-hive-3.1.3_2.12-1.17.2.jar](https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-hive-3.1.3_2.12/1.17.2/flink-sql-connector-hive-3.1.3_2.12-1.17.2.jar)
```

### 3.2 Hive OLAP 查询环境配置 (Batch Querying)
安装 Iceberg Runtime 包，使 Hive 解析引擎能够原生识别并查询由 Flink 实时写入的 Iceberg 表格式数据：

```bash
cd /opt/module/hive-3.1.3/lib/
wget [https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-hive-runtime/1.4.3/iceberg-hive-runtime-1.4.3.jar](https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-hive-runtime/1.4.3/iceberg-hive-runtime-1.4.3.jar)
```

### 3.3 Flink 全局类加载策略调优
为了防止引入的 Iceberg/Hive 连接器与底层 Hadoop 原生包发生类冲突（Jar Hell），需调整 Flink 的类解析优先级。

```bash
nano /opt/module/flink-1.17.2/conf/flink-conf.yaml
```

确保 `flink-conf.yaml` 中包含以下隔离策略：

```yaml
classloader.check-leaked-classloader: false
classloader.resolve-order: parent-first
```

### 3.4 打通 Flink 与 Hive Catalog (SQL 联调打样)

在 Flink SQL 客户端中执行以下 DDL，建立基于 Hive Metastore 的 Iceberg 统一命名空间：

```sql
-- 1. 创建基于 Hive Metastore 托管的 Iceberg Catalog
CREATE CATALOG iceberg_catalog WITH (
  'type'='iceberg',
  'catalog-type'='hive',
  'uri'='thrift://lake-master-01:9083',
  'warehouse'='hdfs:///user/hive/warehouse'
);

-- 2. 切换当前会话至 Iceberg 命名空间
USE CATALOG iceberg_catalog;

-- 假设我们在 Hive 中已预先创建了 ODS 层的 Database
USE iceberg_ods; 

-- 3. 注入流处理核心运行参数
SET 'execution.runtime-mode' = 'streaming';
SET 'table.dml-sync' = 'false';

-- 【关键要求】Iceberg 的数据文件 Commit 操作强依赖于 Flink 的 Checkpoint 机制
-- 必须开启 Checkpoint 才能保证流式数据对外可见！
SET 'execution.checkpointing.interval' = '30s';
```

> **💡 提示：**
> 至此，一个包含底层分布式存储、实时消息总线、流计算引擎、数据湖表格式以及全局元数据血缘治理的**全栈大数据分析平台**已部署完毕。可以正式进入数据的流转摄取与 ETL 开发阶段！