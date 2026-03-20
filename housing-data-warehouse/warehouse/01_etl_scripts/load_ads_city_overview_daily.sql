-- 开启动态分区
SET spark.sql.sources.partitionOverwriteMode = dynamic;
USE ershoufang;
INSERT OVERWRITE TABLE ads_city_overview_daily PARTITION (ds)
WITH base AS (
    SELECT
        ds,
        city,
        total_price,
        unit_price,
        area_sqm,
        CONCAT(CAST(room_num AS STRING), '-', CAST(hall_num AS STRING), '-', CAST(bathroom_num AS STRING)) AS room_type,
        decoration
    FROM dwd_ershoufang_fact
    WHERE room_num IS NOT NULL
      AND hall_num IS NOT NULL
      AND bathroom_num IS NOT NULL
    -- 可选：限制日期范围，例如 AND ds >= '20260201'
),
     city_agg AS (
         SELECT
             ds,
             city,
             COUNT(1) AS total_house_count,
             AVG(total_price) AS avg_total_price,
             PERCENTILE_APPROX(total_price, 0.5) AS median_total_price,
             AVG(unit_price) AS avg_unit_price,
             PERCENTILE_APPROX(unit_price, 0.5) AS median_unit_price,
             AVG(area_sqm) AS avg_area_sqm
         FROM base
         GROUP BY ds, city
     ),
     room_dist AS (
         SELECT
             ds,
             city,
             room_type,
             COUNT(1) AS cnt
         FROM base
         GROUP BY ds, city, room_type
     ),
     room_map AS (
         SELECT
             ds,
             city,
             MAP_FROM_ENTRIES(COLLECT_LIST(STRUCT(room_type, cnt))) AS room_type_distribution
         FROM room_dist
         GROUP BY ds, city
     ),
     decoration_dist AS (
         SELECT
             ds,
             city,
             decoration,
             COUNT(1) AS cnt
         FROM base
         WHERE decoration IS NOT NULL
         GROUP BY ds, city, decoration
     ),
     decoration_map AS (
         SELECT
             ds,
             city,
             MAP_FROM_ENTRIES(COLLECT_LIST(STRUCT(decoration, cnt))) AS decoration_distribution
         FROM decoration_dist
         GROUP BY ds, city
     )
SELECT
    ca.ds,
    ca.city,
    ca.total_house_count,
    ca.avg_total_price,
    ca.median_total_price,
    ca.avg_unit_price,
    ca.median_unit_price,
    ca.avg_area_sqm,
    COALESCE(rm.room_type_distribution, MAP()) AS room_type_distribution,
    COALESCE(dm.decoration_distribution, MAP()) AS decoration_distribution
FROM city_agg ca
         LEFT JOIN room_map rm
                   ON ca.ds = rm.ds AND ca.city = rm.city
         LEFT JOIN decoration_map dm
                   ON ca.ds = dm.ds AND ca.city = dm.city;