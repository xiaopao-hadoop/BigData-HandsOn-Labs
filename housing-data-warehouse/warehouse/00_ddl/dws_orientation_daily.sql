USE ershoufang;
CREATE TABLE IF NOT EXISTS dws_orientation_daily (
                                                     ds                 STRING  COMMENT '数据分区日期，格式yyyyMMdd',
                                                     orientation        STRING  COMMENT '朝向（如“南”、“南北”）',
                                                     house_count        BIGINT  COMMENT '房源数量',
                                                     avg_total_price    DOUBLE  COMMENT '平均总价（万元）',
                                                     median_total_price DOUBLE  COMMENT '中位数总价（万元）',
                                                     avg_unit_price     DOUBLE  COMMENT '平均单价（元/平米）',
                                                     median_unit_price  DOUBLE  COMMENT '中位数单价（元/平米）',
                                                     avg_area_sqm       DOUBLE  COMMENT '平均面积（平米）'
)
    USING iceberg
    PARTITIONED BY (ds)
    COMMENT '朝向维度每日汇总表，按朝向粒度聚合'
    TBLPROPERTIES (
                      'write.format.default' = 'parquet',
                      'write.parquet.compression-codec' = 'zstd',
                      'format-version' = '2'
                  );