# 阶段六：集群踩坑与故障排查指南 

在从零搭建这套包含 Hadoop、Kafka、Flink、Hive、HBase、Atlas 等十余个组件的工业级大数据平台时，不可避免地会遇到各种版本冲突、网络通信和资源调度问题。

本文档提炼了在实际部署和调优过程中沉淀的“血泪史”。当集群出现诡异的异常时，请首先对照此清单进行排查。

## 1. 致命的 `localhost` 解析陷阱

这是分布式集群搭建中最容易被忽视、却又最致命的基础网络问题。

**现象**：
* Zookeeper 集群无法选举 Leader，日志显示连接被拒绝。
* Hadoop DataNode 无法向 NameNode 注册，或者在 Web UI 中显示节点状态为 Dead。
* HBase RegionServer 异常宕机。

**根本原因**：
Ubuntu 系统在初始化时，`/etc/hosts` 文件中默认包含指向 `127.0.0.1` 或 `127.0.1.1` 的 `localhost` 解析。这会导致 Zookeeper 或 Hadoop 组件在注册自身 IP 时，错误地将本地回环地址广播给集群其他节点。

**解决方案**：
* 必须在集群所有机器的 `/etc/hosts` 文件中，**注释或删除**原有的 `localhost` 映射。
* 在配置 Hadoop 的 `workers` 文件以及 HBase 的 `regionservers` 文件时，绝对不能包含 `localhost`，必须写明确的节点主机名（如 `lake-worker-01`）。

## 2. 史诗级依赖灾难：Guava 版本冲突

在大数据生态（尤其是 Hadoop 3.x 与 Hive 3.x 混搭环境）中，Google Guava 库的版本冲突是导致服务闪退的头号元凶。

**现象**：
* Hive Metastore 启动失败，日志抛出 `java.lang.NoSuchMethodError: com.google.common.base.Preconditions.checkArgument`。
* Spark on YARN 提交任务瞬间失败。

**根本原因**：
Hadoop 3.1.3 核心依赖的是 `guava-27.0-jre.jar`，而 Hive 3.1.3 自带的依然是古老的 `guava-19.0.jar`。当引擎进行底层通信时，类加载器加载了低版本包，导致找不到新版本中的方法。

**解决方案**：
1. **统一 Hive 依赖**：删除 Hive `lib` 目录下的老版本，将 Hadoop 的高版本软链接或复制过来。
   ```bash
   rm /opt/module/hive-3.1.3/lib/guava-19.0.jar
   cp $HADOOP_HOME/share/hadoop/common/lib/guava-27.0-jre.jar /opt/module/hive-3.1.3/lib/
   ```
2. **强制 Spark 加载顺序**：在部署 Spark 2.3.0 时，必须在 `spark-defaults.conf` 中显式强制 Driver 和 Executor 优先加载高版本的 Guava 包：
   ```properties
   spark.driver.extraClassPath    /opt/module/hadoop-3.1.3/share/hadoop/common/lib/guava-27.0-jre.jar
   spark.executor.extraClassPath  /opt/module/hadoop-3.1.3/share/hadoop/common/lib/guava-27.0-jre.jar
   spark.driver.userClassPathFirst   true
   spark.executor.userClassPathFirst true
   ```

## 3. 自动化运维脚本：SSH 非交互式登录坑点

**现象**：
编写的批量执行脚本 `xcall.sh` 在执行如 `java -version` 或 `jps` 时，提示 `command not found`，但在机器上手动敲击命令却完全正常。

**根本原因**：
通过 SSH 远程直接执行命令（如 `ssh lake-worker-01 "jps"`）属于**非交互式登录**。这种模式下，系统不会默认加载 `/etc/profile` 或 `~/.bashrc` 中的环境变量，导致找不到 `JAVA_HOME` 和组件的 `bin` 目录。

**解决方案**：
在封装 `xcall.sh` 脚本时，必须加上 `bash -lc` 参数，强制开启一个登录 Shell 来执行命令，从而完整加载环境变量体系：
```bash
ssh $host "bash -lc '$CMD'"
```

## 4. Atlas 与 Solr 的时序依赖与初始化陷阱

**现象**：
Atlas 启动后无法访问 Web UI，查看 `atlas.log` 发现大量连接 Solr 失败或找不到 Index 的报错，服务不断重启。

**根本原因**：
虽然 Atlas 在配置中指定了连接 Solr Cloud，但它自身没有权限或能力在 Solr 中从零创建所需的 Collection（集合）。

**解决方案**：
**严格遵守初始化顺序**。在第一次启动 Atlas 进程之前，必须手动进入 Solr 的目录，利用 Atlas 提供的配置模板，提前建立好三大基石 Collection：
```bash
./solr create -c vertex_index -d /opt/module/atlas-2.3.0/conf/solr -shards 3 -replicationFactor 2 -force
./solr create -c edge_index -d /opt/module/atlas-2.3.0/conf/solr -shards 3 -replicationFactor 2 -force
./solr create -c fulltext_index -d /opt/module/atlas-2.3.0/conf/solr -shards 3 -replicationFactor 2 -force
```
只要索引提前就绪，Atlas 就能顺畅挂载并启动。

## 5. 配置文件中的隐形杀手

**现象**：
Zookeeper 或 Hadoop 启动后立即报错退出，提示配置文件解析异常或路径不存在。

**根本原因**：
在 Windows 环境下编辑文档并复制到 Linux（或使用 nano/vim 手写）时，极易在配置项的末尾混入空格，或者不可见的 Windows 回车符（`\r`）。例如 `zoo.cfg` 中的 `dataDir=/opt/data/zookeeper `（末尾多了空格），Linux 引擎会将其视为包含空格的物理路径去寻找，必然失败。

**解决方案**：
* 养成严谨的运维习惯，复制配置文件后仔细检查行尾。
* 对于脚本文件，如果是在 Windows 下编写的，传到服务器后请务必执行 `sed -i 's/\r$//' script.sh` 进行格式转换，防止 `bad interpreter` 错误。
* 确保 Hadoop 的 `hadoop-env.sh` 末尾静态写死了正确的 `JAVA_HOME` 路径，避免环境变量漂移。