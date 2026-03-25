### 数据集介绍
采用基于**Scrapy**网络爬虫获取的全国二手房真实挂牌数据集。

* **数据量级**：约 45 万条真实房源明细数据。
* **数据字段**：
    * **基础信息**：总价、单价、面积、户型、朝向、楼层、装修、建成年份。
    * **地理位置**：城市、区域、板块、小区名称。
    * **市场热度**：关注人数、发布时间。

### 数据流转结构
整个数据链路涵盖从数据采集到可视化的完整数仓规范，架构如下：

1.  **数据采集**：Python (Scrapy) 分布式爬虫获取源数据，通过 `pipelines.py` 将清洗后的数据推入消息队列。
2.  **数据缓冲**：**Kafka** 作为高吞吐消息队列，承担数据削峰。
3.  **湖仓接入**：**Flink** 消费 Kafka 数据，清洗后流式写入 **Apache Iceberg**，实现ODS层原始数据的湖仓落盘。
4.  **数仓分层 (ETL)**：基于规范的维度建模，在 Iceberg 中构建 **DWD**（事实表）、**DWS**（轻度汇总层）和 **ADS**（应用数据服务层）。
5.  **极速 OLAP**：**StarRocks** 直连 Iceberg 数据湖，实现离线聚合任务与极速查询的结合。
6.  **BI 展现**：**Jupyter Notebook** (结合 Pandas/Matplotlib/Pyecharts) 直连查询 ADS 层。

### 请根据以下步骤对应的脚本文件进行操作。

### Step 1: 数据采集与缓冲 (Python + Kafka)
* 确保 Kafka 集群运行正常，创建对应 Topic。
* 运行爬虫程序，将房源数据源源不断地打入 Kafka。

### Step 2: 湖仓接入层构建 (Flink + Iceberg)
执行 `Kafka-Flink/` 目录下的核心转存脚本：
* 运行 `kafka_to_flink_to_iceberg.sh`。
* 该脚本启动 Flink 任务，消费 Kafka JSON 流，并两阶段提交安全写入 Iceberg 的 **ODS/DWD** 原始表中。

### Step 3: 数仓建模与 ETL 执行 (SQL)
进入 `warehouse/` 目录，按顺序执行：
1.  **建表 (DDL)**：执行 `00_ddl/` 目录下的 SQL 文件。依次创建事实表 (`dwd_ershoufang_fact`)、汇总表 (`dws_*.sql`) 以及应用表 (`ads_*.sql`)。
2.  **跑批 (ETL)**：执行 `01_etl_scripts/` 目录下的 Load 脚本。按照 **DWD -> DWS -> ADS** 链路计算并写入各项核心指标。

### Step 4: 极速 OLAP 引擎配置 (StarRocks)
* 确保 StarRocks 已创建指向 Hive Metastore / Iceberg 的 **External Catalog**。
* BI 查询直接打向 StarRocks 中的 **ADS 层表**，进行极速OLAP查询。

### Step 5: BI 可视化分析 (Jupyter Notebook)
进入 `BI/` 目录，启动 Jupyter 环境。这里可视化分析包含五个模块，可以根据数据自行拓展：
* **市场概览**：全国总房源、均价梯度与装修分布。
* **小区热度与排行**：热门小区词云及板块热度。
* **价格区间与结构**：价格与面积、建成年份的关联分布。
* **户型与朝向分析**：不同户型和朝向的均价及房源数量对比。
* **房源热度与排行**：挖掘高关注房源的底层特征。
