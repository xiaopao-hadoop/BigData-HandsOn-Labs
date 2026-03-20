USE ershoufang;
CREATE TABLE IF NOT EXISTS ads_top10_attention_houses_daily (
                                                                ds                 STRING       COMMENT '数据分区日期，格式yyyyMMdd',
                                                                city               STRING       COMMENT '城市',
                                                                rank               INT          COMMENT '关注数排名（1-10）',
                                                                house_id           STRING       COMMENT '房源ID',
                                                                house_url          STRING       COMMENT '房源详情页URL',
                                                                title              STRING       COMMENT '房源标题',
                                                                community          STRING       COMMENT '小区名称',
                                                                total_price        DOUBLE       COMMENT '总价（万元）',
                                                                unit_price         INT          COMMENT '单价（元/平米）',
                                                                area_sqm           DOUBLE       COMMENT '建筑面积（平米）',
                                                                attention_count    INT          COMMENT '关注人数',
                                                                visit_30_days      INT          COMMENT '30天内带看次数',
                                                                tags               ARRAY<STRING> COMMENT '标签列表'
)
    USING iceberg
    PARTITIONED BY (ds)
    COMMENT '每日各城市关注数TOP10房源明细表'
    TBLPROPERTIES (
                      'write.format.default' = 'parquet',
                      'write.parquet.compression-codec' = 'zstd',
                      'format-version' = '2'
                  );