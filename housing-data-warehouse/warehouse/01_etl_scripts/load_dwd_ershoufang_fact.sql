USE ershoufang;
INSERT OVERWRITE TABLE ershoufang.dwd_ershoufang_fact
PARTITION (ds)
SELECT
    FROM_UNIXTIME(header.event_time, 'yyyyMMdd') AS ds,
    header.event_time,
    header.source,
    header.batch_id,
    header.trace_id,
    core_data.house_id,
    core_data.house_url,
    core_data.title,
    core_data.city,
    CASE WHEN core_data.district = 'TODO_MAPPING' THEN NULL ELSE core_data.district END AS district,
    core_data.neighborhood,
    core_data.community,
    core_data.total_price,
    core_data.unit_price,
    core_data.area_sqm,
    core_data.room_num,
    core_data.hall_num,
    core_data.bathroom_num,
    core_data.orientation,
    core_data.floor_level,
    core_data.floor_total,
    CASE core_data.floor_level
        WHEN '低楼层' THEN 0.25
        WHEN '中楼层' THEN 0.5
        WHEN '高楼层' THEN 0.75
        ELSE 0.0
        END AS floor_ratio,
    core_data.decoration,
    core_data.build_year,
    ext_attributes.tags,
    ext_attributes.follow_info.attention_count,
    ext_attributes.follow_info.visit_30_days,
    ext_attributes.subway_info,
    regexp_extract(ext_attributes.raw_info.p2_desc, '([一二三四五六]环(?:至[一二三四五六]环)?)', 1) AS ring_road,
    ext_attributes.raw_info.p1_desc,
    ext_attributes.raw_info.p2_desc
FROM ershoufang.ods_ershoufang
WHERE
    core_data.city NOT IN ('清远', '西安', '武汉', '青岛', '成都', '重庆');