# 阶段六：极速 OLAP 引擎部署 (StarRocks)

在数据平台的架构中，StarRocks 作为新一代极速全场景 MPP 数据库，承担着向应用层提供亚秒级查询响应的核心职责。本节将记录在 Master 节点 (`lake-master-01`) 上完成 StarRocks FE (前端) 与 BE (后端) 混合部署的过程，并彻底打通与 Iceberg 数据湖的查询链路。



## 1. 基础环境准备与解压

StarRocks 作为高性能 OLAP 引擎，强依赖于操作系统高并发的文件描述符和内存锁定能力。

### 1.1 系统环境调优
在 `lake-master-01` 执行以下命令，修改系统级别的内存映射限制：

```bash
# 临时生效
sysctl -w vm.max_map_count=2000000

# 持久化生效配置
echo "vm.max_map_count=2000000" >> /etc/sysctl.conf
sysctl -p
```

### 1.2 解压与目录规范
将官方二进制包解压至标准组件目录：

```bash
cd /opt/software
# 下载的是官方稳定版的 tar.gz 二进制包
wget https://archive.apache.org/dist/incubator/starrocks/3.1.9/apache-starrocks-3.1.9-incubating.tar.gz -O StarRocks-3.1.9.tar.gz
tar -zxvf StarRocks-3.1.x.tar.gz -C /opt/module/
mv /opt/module/StarRocks-3.1.x /opt/module/starrocks
```

## 2. FE (Frontend) 节点配置与启动

FE 节点负责全局元数据管理、客户端连接接入以及分布式查询规划。

### 2.1 创建元数据目录
> **⚠️ 避坑指南：**
> 必须将元数据物理目录与软件安装目录隔离，防止后续版本升级或误操作时导致核心数据丢失。

```bash
mkdir -p /opt/data/starrocks/fe/meta
```

### 2.2 修改核心配置 `fe.conf`
编辑前端节点配置文件：

```bash
nano /opt/module/starrocks/fe/conf/fe.conf
```

修改及确认以下核心参数：

```properties
# 绑定集群内网通信 IP CIDR，防止绑定到 localhost 导致网络孤岛
priority_networks = 192.168.144.0/24

# 指定刚刚创建的元数据持久化存放路径
meta_dir = /opt/data/starrocks/fe/meta

# JVM 内存调优 (单机混合部署场景下，为 FE 分配 4G 即可，保留计算资源给 BE 和其他组件)
JAVA_OPTS = "-Dlog4j2.formatMsgNoLookups=true -Xmx4096m -XX:+UseG1GC"
```

### 2.3 启动 FE 服务
```bash
# 以后台守护进程模式启动
/opt/module/starrocks/fe/bin/start_fe.sh --daemon
```

> **💡 提示：**
> 启动后通过 `jps` 命令检查，若观测到 `StarRocksFE` 进程，则标志前端服务挂载成功。

## 3. BE (Backend) 节点配置与启动

BE 节点负责底层数据的实际物理存储和分布式查询的向量化执行。

### 3.1 创建存储目录
```bash
mkdir -p /opt/data/starrocks/be/storage
```

### 3.2 修改核心配置 `be.conf`
编辑后端节点配置文件：

```bash
nano /opt/module/starrocks/be/conf/be.conf
```

修改及确认以下核心参数：

```properties
# 绑定内网通信 IP CIDR
priority_networks = 192.168.144.0/24

# 指定数据文件底层存储路径
storage_root_path = /opt/data/starrocks/be/storage

# 确保配置了正确的 Java 运行时环境 (需与全局 my_env.sh 保持绝对一致)
JAVA_HOME = /usr/lib/jvm/java-8-openjdk-amd64
```

### 3.3 启动 BE 服务
```bash
# 以后台守护进程模式启动
/opt/module/starrocks/be/bin/start_be.sh --daemon
```

## 4. 集群组网与拓扑验证

FE 和 BE 虽然已在同一物理节点点火启动，但逻辑上依然相互隔离。我们需要通过 MySQL 通信协议接入 FE，手动将 BE 实例注册到集群计算拓扑中。

### 4.1 接入 FE 终端
StarRocks 完美兼容 MySQL 协议，默认查询接入端口为 `9030`：

```bash
mysql -h lake-master-01 -P 9030 -uroot
```

### 4.2 注册 BE 节点
在 MySQL 交互式终端中执行 DDL 注册指令（BE 的心跳探测端口默认为 `9050`）：

```sql
ALTER SYSTEM ADD BACKEND "lake-master-01:9050";
```

### 4.3 验证集群状态
```sql
-- 检查 FE 状态 (Alive 必须为 true，Role 为 LEADER)
SHOW PROC '/frontends'\G

-- 检查 BE 状态 (Alive 必须为 true)
SHOW PROC '/backends'\G
```

## 5. 打通湖仓一体：创建 Iceberg External Catalog

部署 StarRocks 的核心战略目的之一，是直接对通过 Flink 实时写入 HDFS 的 Iceberg 数据湖进行极速联邦分析，彻底免去繁琐的数据搬迁 (ETL) 过程。



在 StarRocks 的 MySQL 终端中执行以下 DDL，直接映射并挂载 Hive Metastore 中纳管的 Iceberg 目录：

```sql
CREATE EXTERNAL CATALOG iceberg_catalog
PROPERTIES (
    "type" = "iceberg",
    "iceberg.catalog.type" = "hive",
    "hive.metastore.uris" = "thrift://lake-master-01:9083"
);

-- 切换会话至外部 Catalog 进行极速联邦查询
SET CATALOG iceberg_catalog;
SHOW DATABASES;

-- 接下来即可直接使用 SELECT 语句，实现对数据湖中 ODS/DWD 层宽表的亚秒级探索
```