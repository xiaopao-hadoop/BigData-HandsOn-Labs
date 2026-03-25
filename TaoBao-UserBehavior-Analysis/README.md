### 数据集介绍
采用阿里天池开源的淘宝用户行为数据集 **UserBehavior.csv** 。

* **数据量级**：约 1 亿条明细数据（约 4GB）。
* **数据字段**：包含用户 ID (`user_id`)、商品 ID (`item_id`)、商品类目 ID (`category_id`)、行为类型 (`behavior`: pv, buy, cart, fav) 和时间戳 (`ts`)。

### 数据流转结构
整个数据链路呈单向流动，职责分离，架构如下：

1.  **数据生成**：Python 脚本模拟电商后端埋点，将 CSV 数据转换为带时间戳的 JSON 流，原速推入消息队列。
2.  **数据缓冲**：**Kafka** 作为高吞吐消息队列，承担数据削峰与持久化。
3.  **流处理ETL**：**Flink SQL** 消费 Kafka 数据，清洗后利用窗口函数进行微批预聚合。
4.  **数据湖存储**：**Apache Iceberg** 接收 Flink 的两阶段提交，实现数据的海量存储与 ACID 事务保障。
5.  **极速 OLAP**：**StarRocks** 通过 External Catalog 零搬运直连 Iceberg，将海量事实表与本地维度表进行联邦查询与逻辑视图封装。
6.  **BI 大屏**：**Tableau** 通过 ODBC 驱动直连 StarRocks，利用 Auto Refresh 插件实现准实时数据自动大屏渲染。


### 请根据以下步骤对应的脚本文件进行操作。

### Step 1: 消息队列构建 (Kafka)
使用 `kafka.sh` 脚本在集群中创建数据通道。
* 配置为 2 个分区（匹配后续 Flink 的并行度），3 个副本（保证高可用）。
* 创建完成后，可开启 Console Consumer 监听端口，验证数据写入。

### Step 2: 数据源模拟 (Python)
运行 `mock_data_producer.py` 模拟真实业务打点。
* **内存保护**：采用文件迭代器逐行读取 4GB 数据，防止脚本 OOM。
* **断点续传**：脚本每发送 10000 条会自动记录 offset。意外中断后重启，会自动从上次的行号继续发送。

### Step 3: 实时湖仓 ETL (Flink + Iceberg)
通过 `flink.sh` 启动 Flink SQL 客户端并执行核心数据链路：
* **ODS 层**：对接 Kafka，清洗并转换为带 Watermark 的动态表。
* **DWD 层**：过滤异常空值，提取合法的行为明细，流式写入 Iceberg。
* **DWS 层**：针对类目流量榜和用户行为漏斗，利用 10 分钟 `TUMBLE` 窗口在内存中完成聚合，再通过 Iceberg 的两阶段提交落盘，防止底层数据库被海量 INSERT 击穿。

### Step 4: 极速 OLAP 分析 (StarRocks)
使用 `starrocks.sh` 配置查询加速层：
* 挂载 **External Catalog** (taobao_lake)，打通 Hive Metastore 元数据。
* 在本地数据库创建并导入维度表 `dim_category`。
* **视图封装**：在 StarRocks 中创建 `view_category_metrics` 和 `view_behavior_funnel`，将跨库 JOIN 逻辑下推到数据库层。

### Step 5: BI 大屏渲染 (Tableau)
* 这里通过MySQL接口直接连接StarRocks，之后就是正常的BI可视化操作。

