USE ershoufang;
CREATE TABLE IF NOT EXISTS ads_hot_communities_daily (
                                                         ds                 STRING  COMMENT '数据分区日期，格式yyyyMMdd',
                                                         city               STRING  COMMENT '城市',
                                                         district           STRING  COMMENT '区域',
                                                         neighborhood       STRING  COMMENT '板块',
                                                         community          STRING  COMMENT '小区名称',
                                                         house_count        BIGINT  COMMENT '房源数量',
                                                         avg_total_price    DOUBLE  COMMENT '平均总价（万元）',
                                                         avg_unit_price     DOUBLE  COMMENT '平均单价（元/平米）',
                                                         avg_area_sqm       DOUBLE  COMMENT '平均面积（平米）',
                                                         total_attention    BIGINT  COMMENT '总关注人数（该小区所有房源关注数之和）',
                                                         total_visit_30     BIGINT  COMMENT '总30天内带看次数（该小区所有房源带看数之和）',
                                                         avg_attention      DOUBLE  COMMENT '平均关注人数',
                                                         avg_visit_30       DOUBLE  COMMENT '平均30天内带看次数',
                                                         rank_by_attention  INT     COMMENT '按总关注数排名（热度排名）',
                                                         rank_by_visit      INT     COMMENT '按总带看数排名'
)
    USING iceberg
    PARTITIONED BY (ds)
    COMMENT '小区热度每日榜单，按关注/带看数排序'
    TBLPROPERTIES (
                      'write.format.default' = 'parquet',
                      'write.parquet.compression-codec' = 'zstd',
                      'format-version' = '2'
                  );