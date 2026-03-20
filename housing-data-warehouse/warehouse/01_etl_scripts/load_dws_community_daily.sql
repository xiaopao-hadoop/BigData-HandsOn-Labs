-- 开启动态分区
SET spark.sql.sources.partitionOverwriteMode = dynamic;
use ershoufang;
INSERT OVERWRITE TABLE dws_community_daily PARTITION (ds)
WITH base_all AS (
    -- 所有房源（包括缺失户型信息的）
    SELECT
        city,
        district,
        neighborhood,
        community,
        total_price,
        unit_price,
        area_sqm,
        attention_count,
        visit_30_days,
        tags,
        ds
    FROM dwd_ershoufang_fact
    WHERE 1=1
    -- 可选：限制日期范围，例如最近30天
    -- AND ds >= '20260201'
),
     base_agg AS (
         -- 基础指标聚合（包含所有房源）
         SELECT
             city,
             district,
             neighborhood,
             community,
             COUNT(1) AS house_count,
             AVG(total_price) AS avg_total_price,
             PERCENTILE_APPROX(total_price, 0.5) AS median_total_price,
             MIN(total_price) AS min_total_price,
             MAX(total_price) AS max_total_price,
             AVG(unit_price) AS avg_unit_price,
             PERCENTILE_APPROX(unit_price, 0.5) AS median_unit_price,
             AVG(area_sqm) AS avg_area_sqm,
             AVG(attention_count) AS avg_attention_count,
             AVG(visit_30_days) AS avg_visit_30_days,
             ds
         FROM base_all
         GROUP BY city, district, neighborhood, community, ds
     ),
     base_valid_room AS (
         -- 仅包含有效户型信息的房源（用于户型分布）
         SELECT
             city,
             district,
             neighborhood,
             community,
             CONCAT(CAST(room_num AS STRING), '-', CAST(hall_num AS STRING), '-', CAST(bathroom_num AS STRING)) AS room_type,
             ds
         FROM dwd_ershoufang_fact
         WHERE room_num IS NOT NULL
           AND hall_num IS NOT NULL
           AND bathroom_num IS NOT NULL
         -- 保持与 base_all 相同的过滤条件（如日期范围）
         -- AND ds >= '20260201'
     ),
     room_type_agg AS (
         SELECT
             city,
             district,
             neighborhood,
             community,
             room_type,
             COUNT(1) AS room_count,
             ds
         FROM base_valid_room
         WHERE room_type IS NOT NULL   -- 安全起见
         GROUP BY city, district, neighborhood, community, room_type, ds
     ),
     room_type_map AS (
         SELECT
             city,
             district,
             neighborhood,
             community,
             MAP_FROM_ENTRIES(COLLECT_LIST(STRUCT(room_type, room_count))) AS room_type_distribution,
             ds
         FROM room_type_agg
         GROUP BY city, district, neighborhood, community, ds
     ),
     tag_freq AS (
         -- 标签统计（基于所有房源）
         SELECT
             city,
             district,
             neighborhood,
             community,
             tag,
             COUNT(1) AS tag_count,
             ds
         FROM base_all
                  LATERAL VIEW EXPLODE(tags) t AS tag
         WHERE tags IS NOT NULL AND tag IS NOT NULL AND tag != ''
         GROUP BY city, district, neighborhood, community, tag, ds
     ),
     hot_tags AS (
         SELECT
             city,
             district,
             neighborhood,
             community,
             SLICE(
                     TRANSFORM(
                             SORT_ARRAY(COLLECT_LIST(STRUCT(tag_count, tag)), FALSE),
                             x -> x.tag
                     ),
                     1,
                     5
             ) AS hot_tags,
             ds
         FROM tag_freq
         GROUP BY city, district, neighborhood, community, ds
     )
-- 最终 SELECT 字段顺序严格按照表定义（ds 在第一位）
SELECT
    ba.ds,
    ba.city,
    ba.district,
    ba.neighborhood,
    ba.community,
    ba.house_count,
    ba.avg_total_price,
    ba.median_total_price,
    ba.min_total_price,
    ba.max_total_price,
    ba.avg_unit_price,
    ba.median_unit_price,
    ba.avg_area_sqm,
    COALESCE(rm.room_type_distribution, MAP()) AS room_type_distribution,
    ba.avg_attention_count,
    ba.avg_visit_30_days,
    COALESCE(ht.hot_tags, ARRAY()) AS hot_tags
FROM base_agg ba
         LEFT JOIN room_type_map rm
                   ON ba.city = rm.city
                       AND ba.district = rm.district
                       AND ba.neighborhood = rm.neighborhood
                       AND ba.community = rm.community
                       AND ba.ds = rm.ds
         LEFT JOIN hot_tags ht
                   ON ba.city = ht.city
                       AND ba.district = ht.district
                       AND ba.neighborhood = ht.neighborhood
                       AND ba.community = ht.community
                       AND ba.ds = ht.ds;