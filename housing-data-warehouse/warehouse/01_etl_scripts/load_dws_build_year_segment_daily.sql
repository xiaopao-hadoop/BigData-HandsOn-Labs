-- 开启动态分区
SET spark.sql.sources.partitionOverwriteMode = dynamic;
USE ershoufang;
INSERT OVERWRITE TABLE dws_build_year_segment_daily PARTITION (ds)
SELECT
    ds,
    CASE
        WHEN build_year < 1990 THEN '1990前'
        WHEN build_year >= 1990 AND build_year < 2000 THEN '1990-2000'
        WHEN build_year >= 2000 AND build_year < 2010 THEN '2000-2010'
        WHEN build_year >= 2010 THEN '2010后'
        ELSE '未知'
        END AS year_segment,
    COUNT(1) AS house_count,
    AVG(total_price) AS avg_total_price,
    PERCENTILE_APPROX(total_price, 0.5) AS median_total_price,
    AVG(unit_price) AS avg_unit_price,
    PERCENTILE_APPROX(unit_price, 0.5) AS median_unit_price,
    AVG(area_sqm) AS avg_area_sqm
FROM dwd_ershoufang_fact
WHERE build_year IS NOT NULL   -- 可选：过滤未知建造年份，也可保留为'未知'
GROUP BY ds, year_segment;