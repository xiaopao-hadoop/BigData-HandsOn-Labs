USE ershoufang;
CREATE TABLE IF NOT EXISTS dws_build_year_segment_daily (
                                                            ds                 STRING  COMMENT '数据分区日期，格式yyyyMMdd',
                                                            segment            STRING  COMMENT '建造年份分段（如“1990前”、“1990-2000”、“2000-2010”、“2010-2020”、“2020后”）',
                                                            house_count        BIGINT  COMMENT '房源数量',
                                                            avg_total_price    DOUBLE  COMMENT '平均总价（万元）',
                                                            median_total_price DOUBLE  COMMENT '中位数总价（万元）',
                                                            avg_unit_price     DOUBLE  COMMENT '平均单价（元/平米）',
                                                            median_unit_price  DOUBLE  COMMENT '中位数单价（元/平米）',
                                                            avg_area_sqm       DOUBLE  COMMENT '平均面积（平米）'
)
    USING iceberg
    PARTITIONED BY (ds)
    COMMENT '建造年份分段每日汇总表，按年份分段粒度聚合'
    TBLPROPERTIES (
                      'write.format.default' = 'parquet',
                      'write.parquet.compression-codec' = 'zstd',
                      'format-version' = '2'
                  );