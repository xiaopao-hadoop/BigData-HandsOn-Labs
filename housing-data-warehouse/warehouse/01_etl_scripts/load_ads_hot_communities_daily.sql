SET spark.sql.sources.partitionOverwriteMode = dynamic;
USE ershoufang;
INSERT OVERWRITE TABLE ads_hot_communities_daily PARTITION (ds)
WITH base AS (
    SELECT
        ds,
        city,
        district,
        neighborhood,
        community,
        total_price,
        unit_price,
        area_sqm,
        attention_count,
        visit_30_days
    FROM dwd_ershoufang_fact
    -- 过滤掉关注和带看都为0或null的记录（保持热度榜单有意义）
    WHERE (attention_count > 0 OR visit_30_days > 0)
      AND attention_count IS NOT NULL
      AND visit_30_days IS NOT NULL
),
     agg AS (
         SELECT
             ds,
             city,
             district,
             neighborhood,
             community,
             COUNT(1) AS house_count,
             AVG(total_price) AS avg_total_price,
             AVG(unit_price) AS avg_unit_price,
             AVG(area_sqm) AS avg_area_sqm,
             SUM(attention_count) AS total_attention,
             SUM(visit_30_days) AS total_visit_30,
             AVG(attention_count) AS avg_attention,
             AVG(visit_30_days) AS avg_visit_30
         FROM base
         GROUP BY ds, city, district, neighborhood, community
     ),
     ranked AS (
         SELECT
             ds,
             city,
             district,
             neighborhood,
             community,
             house_count,
             avg_total_price,
             avg_unit_price,
             avg_area_sqm,
             total_attention,
             total_visit_30,
             avg_attention,
             avg_visit_30,
             ROW_NUMBER() OVER (PARTITION BY ds ORDER BY total_attention DESC) AS rank_by_attention,
             ROW_NUMBER() OVER (PARTITION BY ds ORDER BY total_visit_30 DESC) AS rank_by_visit
         FROM agg
     )
SELECT
    ds,
    city,
    district,
    neighborhood,
    community,
    house_count,
    avg_total_price,
    avg_unit_price,
    avg_area_sqm,
    total_attention,
    total_visit_30,
    avg_attention,
    avg_visit_30,
    rank_by_attention,
    rank_by_visit
FROM ranked
-- 可选：只保留排名前100的小区，减少数据量（业务按需调整）
WHERE rank_by_attention <= 100 OR rank_by_visit <= 100;