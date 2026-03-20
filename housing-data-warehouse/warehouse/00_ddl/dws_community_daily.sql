-- 建表语句：dws_community_daily
-- 运行环境：Spark SQL (通过 DataGrip 连接 Spark Thrift Server)
-- 存储格式：Apache Iceberg
-- 分区字段：ds (数据日期，格式 yyyyMMdd)
USE ershoufang;
CREATE TABLE IF NOT EXISTS dws_community_daily (
                                                   ds                      STRING COMMENT '数据分区日期，格式yyyyMMdd',
                                                   city                    STRING COMMENT '城市',
                                                   district                STRING COMMENT '区域',
                                                   neighborhood            STRING COMMENT '板块',
                                                   community               STRING COMMENT '小区名称',
                                                   house_count             BIGINT COMMENT '房源数量',
                                                   avg_total_price         DOUBLE COMMENT '平均总价（万元）',
                                                   median_total_price      DOUBLE COMMENT '中位数总价（万元）',
                                                   min_total_price         DOUBLE COMMENT '最小总价（万元）',
                                                   max_total_price         DOUBLE COMMENT '最大总价（万元）',
                                                   avg_unit_price          DOUBLE COMMENT '平均单价（元/平米）',
                                                   median_unit_price       DOUBLE COMMENT '中位数单价（元/平米）',
                                                   avg_area_sqm            DOUBLE COMMENT '平均面积（平米）',
                                                   room_type_distribution  MAP<STRING, INT> COMMENT '户型分布，键为"室-厅-卫"格式（如"3-2-1"），值为房源数量',
                                                   avg_attention_count     DOUBLE COMMENT '平均关注人数',
                                                   avg_visit_30_days       DOUBLE COMMENT '平均30天内带看次数',
                                                   hot_tags                ARRAY<STRING> COMMENT '热门标签（按出现频率排序的前N个标签）'
)
    USING iceberg
    PARTITIONED BY (ds)
    COMMENT '小区维度每日汇总表，按城市+区域+板块+小区粒度聚合'
    TBLPROPERTIES (
                      'write.format.default' = 'parquet',
                      'write.parquet.compression-codec' = 'zstd',
                      'format-version' = '2'
                  );