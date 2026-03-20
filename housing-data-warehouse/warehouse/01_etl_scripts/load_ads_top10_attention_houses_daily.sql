-- 开启动态分区覆盖模式
SET spark.sql.sources.partitionOverwriteMode = dynamic;
USE ershoufang;
INSERT OVERWRITE TABLE ads_top10_attention_houses_daily PARTITION (ds)
WITH ranked AS (
    SELECT
        ds,
        city,
        house_id,
        house_url,
        title,
        community,
        total_price,
        unit_price,
        area_sqm,
        attention_count,
        visit_30_days,
        tags,
        ROW_NUMBER() OVER (PARTITION BY ds, city ORDER BY attention_count DESC) AS rn
    FROM dwd_ershoufang_fact
    WHERE attention_count IS NOT NULL
      AND attention_count > 0
      -- 可选：限制日期范围，如 AND ds >= '20260201'
)
SELECT
    ds,
    city,
    rn AS rank,
    house_id,
    house_url,
    title,
    community,
    total_price,
    unit_price,
    area_sqm,
    attention_count,
    visit_30_days,
    tags
FROM ranked
WHERE rn <= 10;