USE ershoufang;
CREATE TABLE IF NOT EXISTS ads_price_range_distribution_daily (
                                                                  ds                 STRING  COMMENT '数据分区日期，格式yyyyMMdd',
                                                                  price_range        STRING  COMMENT '价格区间，如"0-100万"',
                                                                  house_count        BIGINT  COMMENT '区间内房源数量',
                                                                  percentage         DOUBLE  COMMENT '占当日总房源的比例（百分比）',
                                                                  avg_area_sqm       DOUBLE  COMMENT '区间内平均面积（平米）',
                                                                  avg_build_year     DOUBLE  COMMENT '区间内平均建成年份',
                                                                  avg_total_price    DOUBLE  COMMENT '区间内平均总价（万元）',
                                                                  avg_unit_price     DOUBLE  COMMENT '区间内平均单价（元/平米）'
)
    USING iceberg
    PARTITIONED BY (ds)
    COMMENT '价格区间每日分布表'
    TBLPROPERTIES (
                      'write.format.default' = 'parquet',
                      'write.parquet.compression-codec' = 'zstd',
                      'format-version' = '2'
                  );