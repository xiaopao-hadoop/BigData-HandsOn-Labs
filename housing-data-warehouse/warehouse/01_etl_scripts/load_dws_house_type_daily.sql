-- 开启动态分区覆盖模式
SET spark.sql.sources.partitionOverwriteMode = dynamic;
use ershoufang;
-- 插入数据到 dws_house_type_daily，使用动态分区
INSERT OVERWRITE TABLE dws_house_type_daily PARTITION (ds)
SELECT
    ds,                                   
    room_num,
    hall_num,
    bathroom_num,
    COUNT(1) AS house_count,
    AVG(total_price) AS avg_total_price,
    PERCENTILE_APPROX(total_price, 0.5) AS median_total_price,
    AVG(unit_price) AS avg_unit_price,
    PERCENTILE_APPROX(unit_price, 0.5) AS median_unit_price,
    AVG(area_sqm) AS avg_area_sqm
FROM dwd_ershoufang_fact
WHERE room_num IS NOT NULL
  AND hall_num IS NOT NULL
  AND bathroom_num IS NOT NULL
-- 可选：若只想处理最近一段时间，可添加 ds 过滤条件，例如：
-- AND ds >= '20260201'
GROUP BY ds, room_num, hall_num, bathroom_num;