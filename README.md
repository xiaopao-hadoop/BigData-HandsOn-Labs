#  BigData-HandsOn-Labs

> **“从零搭建工业级大数据集群，实战全链路数据开发与分析。”**

这是一个基于 Apache Hadoop 生态（涵盖离线批处理与 Flink 实时流计算）的大数据平台部署教程与实战项目集。本项目旨在为大数据初学者提供一份**保姆级的集群部署指南**，同时积累从数据采集、流批处理、数据湖仓建设到 OLAP 分析的**全栈数据开发与分析实战案例**。

---

## 架构与导航 

本repo涵盖了从底层基座到上层应用的完整数据流转链路：

![System Architecture](./assets/集群系统架构.png) 

**快速导航：**
* 📚 **[集群部署保姆级教程 (Cluster-Deployment-Docs)](https://github.com/xiaopao-hadoop/BigData-HandsOn-Labs/tree/main/Cluster-Deployment-Docs)**：包含各类中间件和计算引擎的详细安装与配置步骤。
* 🏗️ **[系统架构图与静态资源 (assets)](https://github.com/xiaopao-hadoop/BigData-HandsOn-Labs/tree/main/assets)**：项目架构图、ER 图及其他说明性图片资源。
* 🏠 **[实战项目一：二手房数据湖仓一体分析 (housing-data-warehouse)](https://github.com/xiaopao-hadoop/BigData-HandsOn-Labs/tree/main/housing-data-warehouse)**：基于离线数仓的端到端数据采集、建模与分析项目。

---

## Wishes:

通过运用不同的技术栈配合数据实战项目：

* **构建工业级思维：** 摆脱单机玩具脚本，掌握分布式集群的资源调度、组件协同与系统调优。
* **吃透全链路技术：** 熟练运用 Python/SQL/Shell 串联数据采集、清洗、分层建模 (ODS-DWD-DWS-ADS) 与高效查询。
* **流批一体化实践：** 通过实战项目，深刻理解 Lambda/Kappa 架构，积累海量数据的离线批处理与高吞吐的实时流计算经验。

---

## 技术栈 

* **编程语言：** Python (数据采集/数据分析), SQL (复杂指标聚合与数仓建模), Shell (自动化脚本)
* **计算引擎：** Apache Spark (Spark SQL 离线批处理), Apache Flink (实时流计算)
* **存储与湖仓：** Hadoop HDFS, Apache Hive (数仓分层), Apache Iceberg (数据湖格式)
* **极速 OLAP：** StarRocks (亚秒级多维分析)
* **数据管道与中间件：** Apache Kafka (消息队列), DataX (异构数据同步)
* **集群管理与治理：** YARN (资源调度), Apache Zookeeper, Apache Atlas (数据血缘追踪)

---

## 实战项目 


| 项目主题 | 数据量 | 数据流/处理方式 | 核心技术栈 | 数据集来源 | 简介 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| [二手房数据湖仓一体分析](https://github.com/xiaopao-hadoop/BigData-HandsOn-Labs/tree/main/housing-data-warehouse) | 450k|离线批处理 (T+1) | Scrapy + Hive + Spark SQL + Flink + Iceberg + StarRocks | [网络爬虫](https://www.kaggle.com/datasets/xiaopaohadoop/second-hand-housing-dataset) | 模拟了真实的离线数仓建设流程。项目从编写分布式爬虫获取源数据开始，通过 Spark 将数据离线同步至数仓 ODS 层。核心亮点在于利用 **Flink** 与 **Apache Iceberg** 构建了稳健的 DWD/DWS 分层模型 |
| [淘宝用户点击数据实时流计算](https://github.com/xiaopao-hadoop/BigData-HandsOn-Labs/tree/main/TaoBao-UserBehavior-Analysis) | 100M | 实时流处理 (微批 T+0) | Python + Kafka + Flink + Iceberg + StarRocks + Tableau | [天池开源数据集](https://tianchi.aliyun.com/dataset/649) | 模拟电商高并发埋点流，打通端到端实时大屏链路。核心亮点在于利用 Flink 时间窗口避免状态爆炸，通过 Iceberg 读写分离解决流式写入的小文件灾难，借助 StarRocks 视图下推与数据源隔离。 |



