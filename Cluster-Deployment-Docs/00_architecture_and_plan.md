# 阶段零：系统规划与架构设计

本文档是整个基于Vmware虚拟机的全栈大数据分析平台部署的基础。在开始任何软件的安装与配置之前，我们必须先从全局视角明确系统的网络拓扑、目录规范以及组件的分布策略。良好的前期规划是保障后续复杂数据管道稳定运行的基石。

## 1. 操作系统与网络规划

考虑到虚拟机和windows后期的交互，这里统一采用配置静态 IP（也就是虚拟机NAT模式）。

* **操作系统**：Ubuntu 22.04.3 服务器版 
* **网络架构**：采用 3 台节点构成的集群，具体映射关系如下：

| 主机名 (Hostname) | 静态 IP 地址 (IP Address) | 节点角色定位 |
| :--- | :--- | :--- |
| `lake-master-01` | `192.168.1xx.101` | 主节点 (Master) / 协调与元数据中心  |
| `lake-worker-01` | `192.168.1xx.102` | 工作节点 01 (Worker) / 计算与存储节点 |
| `lake-worker-02` | `192.168.1xx.103` | 工作节点 02 (Worker) / 计算与存储节点 |

## 2. 全局目录规范

为了防止后期组件安装混乱、日志侵占系统盘空间等问题，必须在所有节点上严格遵守统一的目录规划。所有大数据组件及其产生的数据均挂载在 `/opt` 目录下。

* `/opt/software`：统一存放所有下载的第三方组件压缩包及安装文件。
* `/opt/module`：统一存放所有解压并配置完成的大数据组件运行实例。
* `/opt/data`：存放各组件运行过程中产生的持久化数据。
* `/opt/logs`：统一集中存放各组件的运行日志，便于后续使用工具进行采集和故障排查。

## 3. 核心组件分布矩阵

本集群融合了批处理、实时流计算以及数据治理生态。在有限的虚拟机资源下，合理的组件分布能最大化利用系统资源。以下是规划的组件部署矩阵：

| 组件名称 | lake-master-01 (101) | lake-worker-01 (102) | lake-worker-02 (103) |
| :--- | :--- | :--- | :--- |
| **HDFS** | NameNode, DataNode  | SecondaryNameNode, DataNode  | DataNode  |
| **YARN** | ResourceManager, NodeManager  | NodeManager  | NodeManager  |
| **Zookeeper** | ZK Server (Leader/Follower)  | ZK Server (Leader/Follower) | ZK Server (Leader/Follower)  |
| **Kafka** | Broker (id=0)  | Broker (id=1)  | Broker (id=2)  |
| **HBase** | HMaster  | RegionServer  | RegionServer  |
| **Solr (Cloud 模式)** | Solr Node  | Solr Node  | Solr Node  |
| **MySQL** | MySQL Server  | - | - |
| **Hive** | Metastore, HiveServer2  | - | - |
| **Spark (on YARN)** | History Server  | - | - |
| **Atlas** | Atlas Server  | - | - |
| **Flink (on YARN)** | Flink Client (提交节点)  | TaskManager (YARN 动态分配)  | TaskManager (YARN 动态分配)  |
| **StarRocks** | FE  | BE | BE |

## 4. 全局环境变量与批量管控脚本策略

面对分布式集群，利用脚本可以提高配置效率：

1. **统一环境变量注入**：
   在 Master 节点统一编写 `/etc/profile.d/my_env.sh` 脚本，随后通过 `scp` 命令/`xsync.sh`结合后续的批量同步工具分发至所有 Worker 节点。
2. **xcall.sh 批量执行脚本**：
   引入自定义的 `xcall.sh` 脚本，借助 SSH 免密登录机制，实现“一端输入，全网执行”。例如，分发环境变量后，可通过该脚本一键完成配置文件的移动并授予执行权限：`/home/hadoop/xcall.sh "sudo mv ~/my_env.sh /etc/profile.d/my_env.sh && sudo chmod +x /etc/profile.d/my_env.sh"` 。

