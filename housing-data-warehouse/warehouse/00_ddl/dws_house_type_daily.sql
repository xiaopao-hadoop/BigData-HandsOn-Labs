use ershoufang;
CREATE TABLE IF NOT EXISTS dws_house_type_daily (
                                                    ds                 STRING  COMMENT '数据分区日期，格式yyyyMMdd',
                                                    room_num           INT     COMMENT '室数',
                                                    hall_num           INT     COMMENT '厅数',
                                                    bathroom_num       INT     COMMENT '卫数',
                                                    house_count        BIGINT  COMMENT '房源数量',
                                                    avg_total_price    DOUBLE  COMMENT '平均总价（万元）',
                                                    median_total_price DOUBLE  COMMENT '中位数总价（万元）',
                                                    avg_unit_price     DOUBLE  COMMENT '平均单价（元/平米）',
                                                    median_unit_price  DOUBLE  COMMENT '中位数单价（元/平米）',
                                                    avg_area_sqm       DOUBLE  COMMENT '平均面积（平米）'
)
    USING iceberg
    PARTITIONED BY (ds)
    COMMENT '户型维度每日汇总表，按室数+厅数+卫数粒度聚合'
    TBLPROPERTIES (
                      'write.format.default' = 'parquet',
                      'write.parquet.compression-codec' = 'zstd',
                      'format-version' = '2'
                  );