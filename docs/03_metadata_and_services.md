# 阶段三：元数据与基础服务部署

本阶段我们将部署为整个大数据平台提供协调、元数据管理和全文索引功能的核心基础服务。这些服务是后续流处理引擎（Flink）和数据治理组件（Atlas）正常运行的关键依赖。

## 1. Zookeeper 3.7.1 集群部署 (基础协调服务)

Zookeeper 为 HBase、Kafka、Solr 等组件提供分布式协调和状态管理。

### 1.1 下载与解压
在 Master 节点执行：
```bash
cd /opt/software
# 从 Apache Archive 下载 Zookeeper 3.7.1 二进制包
wget [https://archive.apache.org/dist/zookeeper/zookeeper-3.7.1/apache-zookeeper-3.7.1-bin.tar.gz](https://archive.apache.org/dist/zookeeper/zookeeper-3.7.1/apache-zookeeper-3.7.1-bin.tar.gz)
tar -zxvf apache-zookeeper-3.7.1-bin.tar.gz -C /opt/module/
```

### 1.2 修改核心配置
进入配置目录并基于模板创建配置文件：
```bash
cd /opt/module/zookeeper-3.7.1/conf
cp zoo_sample.cfg zoo.cfg
nano zoo.cfg
```
修改及追加以下内容：
```properties
dataDir=/opt/data/zookeeper
dataLogDir=/opt/logs/zookeeper

# 集群节点配置 (2888为通信端口，3888为选举端口)
server.1=lake-master-01:2888:3888
server.2=lake-worker-01:2888:3888
server.3=lake-worker-02:2888:3888

# 开启四字命令白名单，授权后续 Solr 等组件使用 ruok, mntr, conf 等监控命令
4lw.commands.whitelist=mntr,conf,ruok
```

### 1.3 分发与 myid 标识配置
将配置好的 ZK 分发到两台 Worker 节点：
```bash
scp -r /opt/module/zookeeper-3.7.1 hadoop@lake-worker-01:/opt/module/
scp -r /opt/module/zookeeper-3.7.1 hadoop@lake-worker-02:/opt/module/
```
在**三台机器分别执行**创建数据目录并写入对应的集群 ID：
```bash
# 在 lake-master-01 执行:
mkdir -p /opt/data/zookeeper && echo 1 > /opt/data/zookeeper/myid

# 在 lake-worker-01 执行:
mkdir -p /opt/data/zookeeper && echo 2 > /opt/data/zookeeper/myid

# 在 lake-worker-02 执行:
mkdir -p /opt/data/zookeeper && echo 3 > /opt/data/zookeeper/myid
```

### 1.4 启动 ZK 集群
利用阶段一编写的批量脚本一键启动：
```bash
/home/hadoop/xcall.sh "/opt/module/zookeeper-3.7.1/bin/zkServer.sh start"
```

> **避坑指南**：
> 1. `zoo.cfg` 文件绝对不能包含隐藏字符或多余空格。
> 2. 必须确保 `/etc/hosts` 中已删除或注释 `localhost`，否则 ZK 会监听本地回环地址 `127.0.1.1`，导致集群无法相互通信。

---

## 2. MySQL 8.0 安装与权限配置 (仅 Master 节点)

MySQL 用于存储 Hive 的元数据（Metastore）以及后续数据治理组件的依赖数据。

### 2.1 安装与基础配置
```bash
sudo apt install mysql-server -y
sudo mysql
```

### 2.2 配置远程访问权限与库初始化
在 MySQL 终端内执行（生产环境建议使用高强度密码及专用的非 root 用户）：
```sql
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '123456';
CREATE USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY '123456';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

-- 为后续 Hive 准备元数据库
CREATE DATABASE metastore;
EXIT;
```

### 2.3 开启远程连接监听
修改 MySQL 配置文件：
```bash
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
```
找到 `bind-address = 127.0.0.1` 改为 `0.0.0.0`，然后重启服务：
```bash
sudo systemctl restart mysql
```

---

## 3. Hive 3.1.3 部署 (Metastore 模式)

Hive 提供了基于 SQL 的大数据查询能力。此处我们采用工业界标准的独立 Metastore 部署模式。

### 3.1 下载、解压与依赖冲突解决
```bash
cd /opt/software
wget [https://archive.apache.org/dist/hive/hive-3.1.3/apache-hive-3.1.3-bin.tar.gz](https://archive.apache.org/dist/hive/hive-3.1.3/apache-hive-3.1.3-bin.tar.gz)
tar -zxvf apache-hive-3.1.3-bin.tar.gz -C /opt/module/
mv /opt/module/apache-hive-3.1.3-bin /opt/module/hive-3.1.3
```

> **⚠️ 经典避坑：解决 Guava 版本冲突（必做）**
> Hive 3.1.3 自带的 guava-19.0 与 Hadoop 3.1.3 的 guava-27.0 不兼容，必须替换：
> ```bash
> rm /opt/module/hive-3.1.3/lib/guava-19.0.jar
> cp $HADOOP_HOME/share/hadoop/common/lib/guava-27.0-jre.jar /opt/module/hive-3.1.3/lib/
> ```

下载 MySQL 驱动：
```bash
cd /opt/module/hive-3.1.3/lib/
wget [https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.28/mysql-connector-java-8.0.28.jar](https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.28/mysql-connector-java-8.0.28.jar)
```

### 3.2 配置 `hive-site.xml`
```bash
nano /opt/module/hive-3.1.3/conf/hive-site.xml
```
写入配置，对接 MySQL 和 HDFS：
```xml
<configuration>
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:mysql://lake-master-01:3306/metastore?useSSL=false&amp;allowPublicKeyRetrieval=true&amp;createDatabaseIfNotExist=true</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionDriverName</name>
        <value>com.mysql.cj.jdbc.Driver</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionUserName</name>
        <value>root</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionPassword</name>
        <value>123456</value>
    </property>
    <property>
        <name>hive.metastore.warehouse.dir</name>
        <value>/opt/data/hive/warehouse</value>
    </property>
    <property>
        <name>hive.metastore.uris</name>
        <value>thrift://lake-master-01:9083</value>
    </property>
    <property>
        <name>hive.server2.enable.doAs</name>
        <value>false</value>
    </property>
</configuration>
```

### 3.3 环境变量、初始化与启动
在 `/etc/profile.d/my_env.sh` 中加入 `export HIVE_HOME=/opt/module/hive-3.1.3` 并加入 PATH，执行 `source /etc/profile`。

初始化元数据库：
```bash
schematool -dbType mysql -initSchema
```

后台启动服务：
```bash
mkdir -p /opt/logs/hive
# 启动 Metastore
nohup hive --service metastore >> /opt/logs/hive/metastore.log 2>&1 &
# 启动 HiveServer2 (提供 JDBC 访问，端口 10000)
nohup hive --service hiveserver2 >> /opt/logs/hive/hiveserver2.log 2>&1 &
```

---

## 4. HBase 2.4.17 部署 (Apache Atlas 存储后端)

HBase 提供低延迟的列式存储，本项目中主要作为 Apache Atlas 的图数据库底层存储。

### 4.1 下载与解压
```bash
cd /opt/software
wget [https://archive.apache.org/dist/hbase/2.4.17/hbase-2.4.17-bin.tar.gz](https://archive.apache.org/dist/hbase/2.4.17/hbase-2.4.17-bin.tar.gz)
tar -zxvf hbase-2.4.17-bin.tar.gz -C /opt/module/
```

### 4.2 修改配置
编辑 `hbase-env.sh`：
```bash
nano /opt/module/hbase-2.4.17/conf/hbase-env.sh
```
```bash
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
# 禁用 HBase 内置 ZK，使用我们独立部署的 ZK 集群
export HBASE_MANAGES_ZK=false
export HBASE_LOG_DIR=/opt/logs/hbase
```

编辑 `hbase-site.xml`：
```bash
nano /opt/module/hbase-2.4.17/conf/hbase-site.xml
```
```xml
<configuration>
    <property>
        <name>hbase.rootdir</name>
        <value>hdfs://lake-master-01:8020/hbase</value>
    </property>
    <property>
        <name>hbase.cluster.distributed</name>
        <value>true</value>
    </property>
    <property>
        <name>hbase.zookeeper.quorum</name>
        <value>lake-master-01,lake-worker-01,lake-worker-02</value>
    </property>
    <property>
        <name>hbase.tmp.dir</name>
        <value>/opt/data/hbase/tmp</value>
    </property>
    <property>
        <name>hbase.unsafe.stream.capability.enforce</name>
        <value>false</value>
    </property>
</configuration>
```

编辑 `regionservers` 文件（删除 localhost，写入 Worker 节点）：
```text
lake-worker-01
lake-worker-02
```

### 4.3 分发与启动
```bash
scp -r /opt/module/hbase-2.4.17 hadoop@lake-worker-01:/opt/module/
scp -r /opt/module/hbase-2.4.17 hadoop@lake-worker-02:/opt/module/

# 在 Master 节点启动集群
/opt/module/hbase-2.4.17/bin/start-hbase.sh
```

---

## 5. Solr 8.11.2 部署 (Apache Atlas 索引后端)

Solr 为 Atlas 提供全文检索能力，为支持分布式需以 Cloud 模式运行。

### 5.1 安装与环境准备
```bash
cd /opt/software
wget [https://archive.apache.org/dist/lucene/solr/8.11.2/solr-8.11.2.tgz](https://archive.apache.org/dist/lucene/solr/8.11.2/solr-8.11.2.tgz)
tar -zxvf solr-8.11.2.tgz -C /opt/module/

mkdir -p /opt/data/solr
mkdir -p /opt/logs/solr
```

### 5.2 启动 Solr Cloud 模式
在 `lake-master-01` 上直接以后台 Cloud 模式启动并关联 ZK 集群：
```bash
/opt/module/solr-8.11.2/bin/solr start -cloud \
  -z lake-master-01:2181,lake-worker-01:2181,lake-worker-02:2181 \
  -p 8983 -force
```

---

## 6. Spark 2.3.0 on Hive 部署 (计算引擎替换)

为提升 Hive 的批处理性能，我们将 Hive 的默认执行引擎从 MapReduce 替换为 Spark。

### 6.1 下载专版 Spark
```bash
cd /opt/software
# 下载针对 Hadoop 特化的 without-hadoop 版本，从根本上避免类冲突
wget [https://archive.apache.org/dist/spark/spark-2.3.0/spark-2.3.0-bin-without-hadoop.tgz](https://archive.apache.org/dist/spark/spark-2.3.0/spark-2.3.0-bin-without-hadoop.tgz)
tar -zxvf spark-2.3.0-bin-without-hadoop.tgz -C /opt/module/
mv /opt/module/spark-2.3.0-bin-without-hadoop /opt/module/spark-2.3.0
```

### 6.2 配置 Spark 环境与默认参数
修改 `spark-env.sh`：
```bash
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export HADOOP_CONF_DIR=/opt/module/hadoop-3.1.3/etc/hadoop
# 核心：必须让 Spark 动态获取 Hadoop 的 Classpath
export SPARK_DIST_CLASSPATH=$(hadoop classpath)
```

修改 `spark-defaults.conf` (重点解决 Guava 冲突)：
```properties
spark.master                     yarn
spark.eventLog.enabled           true
spark.eventLog.dir               hdfs://lake-master-01:8020/spark-history
spark.serializer                 org.apache.spark.serializer.KryoSerializer
spark.yarn.historyServer.address lake-master-01:18080

# 强制 Driver 和 Executor 优先加载正确的 Guava 包
spark.driver.extraClassPath      /opt/module/hadoop-3.1.3/share/hadoop/common/lib/guava-27.0-jre.jar
spark.executor.extraClassPath    /opt/module/hadoop-3.1.3/share/hadoop/common/lib/guava-27.0-jre.jar
spark.driver.userClassPathFirst  true
spark.executor.userClassPathFirst true
```

### 6.3 注入依赖与打通 Hive
为 Hive 注入 Spark 核心执行库（采用软链接，保持目录干净）：
```bash
ln -s /opt/module/spark-2.3.0/jars/scala-library-2.11.8.jar /opt/module/hive-3.1.3/lib/
ln -s /opt/module/spark-2.3.0/jars/spark-core_2.11-2.3.0.jar /opt/module/hive-3.1.3/lib/
ln -s /opt/module/spark-2.3.0/jars/spark-network-common_2.11-2.3.0.jar /opt/module/hive-3.1.3/lib/
ln -s /opt/module/spark-2.3.0/jars/spark-network-shuffle_2.11-2.3.0.jar /opt/module/hive-3.1.3/lib/
ln -s /opt/module/spark-2.3.0/jars/spark-rpc_2.11-2.3.0.jar /opt/module/hive-3.1.3/lib/
```

修改 `/opt/module/hive-3.1.3/conf/hive-site.xml`，追加 Spark 引擎配置：
```xml
<property>
    <name>hive.execution.engine</name>
    <value>spark</value>
</property>
<property>
    <name>spark.master</name>
    <value>yarn</value>
</property>
<property>
    <name>spark.yarn.jars</name>
    <value>hdfs://lake-master-01:8020/spark-jars/*</value>
</property>
```

上传 Spark Jar 包到 HDFS（避免每次提交任务重复传输）：
```bash
hadoop fs -mkdir /spark-jars
hadoop fs -put /opt/module/spark-2.3.0/jars/* /spark-jars/
hadoop fs -mkdir -p /spark-history
```

启动 Spark 历史服务器：
```bash
/opt/module/spark-2.3.0/sbin/start-history-server.sh
```

---

## 7. 阶段三验收验证

完成所有组件启动后，请进行以下验证：

1. **Zookeeper**: 执行 `/home/hadoop/xcall.sh "zkServer.sh status"`，检查是否有一台 leader 和两台 follower。
2. **Hive**: 在 Master 节点执行 `beeline -u jdbc:hive2://lake-master-01:10000 -n hadoop`，执行 `show databases;` 应能正常返回。
3. **HBase Web UI**: 访问 `http://192.168.144.101:16010` 查看集群健康状态。
4. **Solr Web UI**: 访问 `http://192.168.144.101:8983`，点击左侧 Cloud -> Tree，查看 `/live_nodes` 下是否成功挂载节点。