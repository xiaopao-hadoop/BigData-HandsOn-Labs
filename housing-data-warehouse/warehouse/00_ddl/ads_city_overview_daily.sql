USE ershoufang;
CREATE TABLE IF NOT EXISTS ads_city_overview_daily (
                                                       ds                      STRING  COMMENT '数据分区日期，格式yyyyMMdd',
                                                       city                    STRING  COMMENT '城市',
                                                       total_house_count       BIGINT  COMMENT '总房源数量',
                                                       avg_total_price         DOUBLE  COMMENT '平均总价（万元）',
                                                       median_total_price      DOUBLE  COMMENT '中位数总价（万元）',
                                                       avg_unit_price          DOUBLE  COMMENT '平均单价（元/平米）',
                                                       median_unit_price       DOUBLE  COMMENT '中位数单价（元/平米）',
                                                       avg_area_sqm            DOUBLE  COMMENT '平均面积（平米）',
                                                       room_type_distribution  MAP<STRING, BIGINT> COMMENT '户型分布，键为"室-厅-卫"格式（如"3-2-1"），值为房源数量',
                                                       decoration_distribution MAP<STRING, BIGINT> COMMENT '装修分布，键为装修类型（如"精装"），值为房源数量'
)
    USING iceberg
    PARTITIONED BY (ds)
    COMMENT '城市级二手房市场每日概览'
    TBLPROPERTIES (
                      'write.format.default' = 'parquet',
                      'write.parquet.compression-codec' = 'zstd',
                      'format-version' = '2'
                  );