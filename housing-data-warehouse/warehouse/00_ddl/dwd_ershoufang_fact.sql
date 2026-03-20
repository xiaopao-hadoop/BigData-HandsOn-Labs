-- 建表语句：dwd_ershoufang_fact
-- 运行环境：Spark SQL (通过 DataGrip 连接 Spark Thrift Server)
-- 存储格式：Apache Iceberg
-- 分区字段：ds (数据日期，格式 yyyyMMdd)
USE ershoufang;
CREATE TABLE IF NOT EXISTS dwd_ershoufang_fact (
                                                   ds                  STRING COMMENT '数据分区日期，格式yyyyMMdd',
                                                   event_time          BIGINT COMMENT '爬取事件时间戳',
                                                   source              STRING COMMENT '数据来源（如5i5j）',
                                                   batch_id            STRING COMMENT '批次ID',
                                                   trace_id            STRING COMMENT '链路追踪ID',
                                                   house_id            STRING COMMENT '房源唯一ID',
                                                   house_url           STRING COMMENT '房源详情页URL',
                                                   title               STRING COMMENT '房源标题',
                                                   city                STRING COMMENT '城市',
                                                   district            STRING COMMENT '区域（需清洗TODO_MAPPING）',
                                                   neighborhood        STRING COMMENT '板块',
                                                   community           STRING COMMENT '小区名称',
                                                   total_price         DOUBLE COMMENT '总价（万元）',
                                                   unit_price          INT COMMENT '单价（元/平米）',
                                                   area_sqm            DOUBLE COMMENT '建筑面积（平米）',
                                                   room_num            INT COMMENT '室数',
                                                   hall_num            INT COMMENT '厅数',
                                                   bathroom_num        INT COMMENT '卫数',
                                                   orientation         STRING COMMENT '朝向（如南北、南）',
                                                   floor_level         STRING COMMENT '楼层层次（低楼层/中楼层/高楼层/未知）',
                                                   floor_total         INT COMMENT '总楼层数',
                                                   floor_ratio         DOUBLE COMMENT '楼层比率（派生，低=0.25,中=0.5,高=0.75,未知=0）',
                                                   decoration          STRING COMMENT '装修情况（精装/简装等）',
                                                   build_year          INT COMMENT '建造年份',
                                                   tags                ARRAY<STRING> COMMENT '标签列表',
                                                   attention_count     INT COMMENT '关注人数',
                                                   visit_30_days       INT COMMENT '30天内带看次数',
                                                   subway_info         STRING COMMENT '地铁信息（线路/距离）',
                                                   ring_road           STRING COMMENT '环线位置（从p2_desc解析，如五环至六环）',
                                                   p1_desc             STRING COMMENT '原始描述p1（保留备用）',
                                                   p2_desc             STRING COMMENT '原始描述p2（保留备用）'
)
    USING iceberg
    PARTITIONED BY (ds)
    COMMENT '二手房明细事实表，每日全量快照，打平ODS嵌套结构并清洗派生'
    TBLPROPERTIES (
                      'write.format.default' = 'parquet',
                      'write.parquet.compression-codec' = 'zstd',
                      'format-version' = '2'
                  );