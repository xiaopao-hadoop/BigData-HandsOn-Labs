-- 开启动态分区覆盖模式
SET spark.sql.sources.partitionOverwriteMode = dynamic;
USE ershoufang;
INSERT OVERWRITE TABLE ads_price_range_distribution_daily PARTITION (ds)
WITH base AS (
    SELECT
        ds,
        total_price,
        area_sqm,
        build_year,
        unit_price,
        -- 价格区间划分（可根据业务需求调整）
        CASE
            WHEN total_price < 100 THEN '0-100万'
            WHEN total_price < 200 THEN '100-200万'
            WHEN total_price < 300 THEN '200-300万'
            WHEN total_price < 400 THEN '300-400万'
            WHEN total_price < 500 THEN '400-500万'
            WHEN total_price < 600 THEN '500-600万'
            WHEN total_price < 700 THEN '600-700万'
            WHEN total_price < 800 THEN '700-800万'
            WHEN total_price < 900 THEN '800-900万'
            WHEN total_price < 1000 THEN '900-1000万'
            ELSE '1000万以上'
            END AS price_range
    FROM dwd_ershoufang_fact
    WHERE total_price IS NOT NULL AND total_price > 0
),
     range_stats AS (
         SELECT
             ds,
             price_range,
             COUNT(1) AS house_count,
             AVG(area_sqm) AS avg_area_sqm,
             AVG(build_year) AS avg_build_year,
             AVG(total_price) AS avg_total_price,
             AVG(unit_price) AS avg_unit_price
         FROM base
         GROUP BY ds, price_range
     ),
     total_per_ds AS (
         SELECT ds, SUM(house_count) AS total_count
         FROM range_stats
         GROUP BY ds
     )
SELECT
    rs.ds,
    rs.price_range,
    rs.house_count,
    ROUND(rs.house_count * 100.0 / tp.total_count, 2) AS percentage,
    rs.avg_area_sqm,
    rs.avg_build_year,
    rs.avg_total_price,
    rs.avg_unit_price
FROM range_stats rs
         JOIN total_per_ds tp ON rs.ds = tp.ds;