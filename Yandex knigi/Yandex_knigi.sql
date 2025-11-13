-- Расчёт MAU авторов

with users as (
    select puid, msk_business_dt_str, main_content_id
    from bookmate.audition
    where extract (month from msk_business_dt_str) = 11
),
authors as (
    select c. main_content_id, c.main_author_id, main_author_name
    from bookmate.content c
    join bookmate.author au on c.main_author_id = au.main_author_id
)
select main_author_name,
count(distinct puid) as mau
from users u 
join authors aut on aut.main_content_id= u.main_content_id
group by main_author_name
order by mau desc
limit 3;


-- Расчёт MAU произведений

with users as (
    select puid, msk_business_dt_str, main_content_id
    from bookmate.audition
    where extract (month from msk_business_dt_str) = 11
),
content as (
    select c. main_content_id, main_content_name, published_topic_title_list, main_author_name
    from bookmate.content c
    join bookmate.author au on c.main_author_id = au.main_author_id
)
select main_content_name, published_topic_title_list, main_author_name,
count(distinct puid) as mau
from users u 
join content c on c.main_content_id= u.main_content_id
group by main_content_name, published_topic_title_list, main_author_name
order by mau desc
limit 3;


-- Расчёт Retention Rate

WITH
users_on_dec2 AS (
    SELECT DISTINCT puid
    FROM bookmate.audition
    WHERE msk_business_dt_str = '2024-12-02'
),
all_activities AS (
    SELECT
        a.puid,
        a.msk_business_dt_str AS event_date
    FROM bookmate.audition a
    INNER JOIN users_on_dec2 u ON a.puid = u.puid
    WHERE a.msk_business_dt_str >= '2024-12-02'
),
activities_with_days AS (
    SELECT
        puid,
        event_date,
        (CAST(event_date AS DATE) - DATE '2024-12-02') AS day_since_install
    FROM all_activities
),
summary AS (
    SELECT
        day_since_install,
        COUNT(DISTINCT puid) AS retained_users
    FROM activities_with_days
    GROUP BY day_since_install
)
SELECT
    day_since_install,
    retained_users,
    ROUND(
        retained_users::numeric / 
        MAX(retained_users) OVER ()    
        ,2
    ) AS retention_rate
FROM summary
ORDER BY day_since_install ASC;


-- Расчёт LTV

WITH user_activity AS(
    SELECT
        usage_geo_id_name AS city,
        puid,
        COUNT(DISTINCT DATE_TRUNC('month', msk_business_dt_str::date)) AS active_months
    FROM bookmate.audition a
    JOIN bookmate.geo g ON a.usage_geo_id = g.usage_geo_id
    WHERE usage_geo_id_name IN ('Москва', 'Санкт-Петербург')
    GROUP BY usage_geo_id_name, puid
)
SELECT 
    city,
    COUNT(puid) AS total_users,
    ROUND(SUM(active_months)::numeric * 399 / COUNT(puid)::numeric, 2) AS ltv
FROM user_activity
GROUP BY city;


-- Расчёт средней выручки прослушанного часа — аналог среднего чека

WITH audition_cast AS (
    SELECT 
        DATE_TRUNC('month', msk_business_dt_str::date)::date AS month,
        puid,
        hours
    FROM bookmate.audition
    WHERE msk_business_dt_str::date >= DATE '2024-09-01'
      AND msk_business_dt_str::date < DATE '2024-12-01'
),
monthly AS (
    SELECT 
        month,
        COUNT(DISTINCT puid) AS mau,
        SUM(hours) AS hours
    FROM audition_cast
    GROUP BY month
)
SELECT 
    month,
    mau,
    ROUND(hours::numeric, 2) AS hours,
    ROUND((mau * 399.0)::numeric / NULLIF(hours, 0), 2) AS avg_hour_rev
FROM monthly
ORDER BY month DESC;

-- Подготовка данных  к такому виду, который будет пригодным для проверки гипотезы в Python. 
-- Отбор пользователей только из Москвы и Санкт-Петербурга и вывод их активности - суммы часов.

select usage_geo_id_name as city,
puid,
sum(hours:: numeric) as hours
from bookmate.audition a
join bookmate.geo g on a.usage_geo_id = g.usage_geo_id
where usage_geo_id_name in ('Москва', 'Санкт-Петербург')
group by usage_geo_id_name, puid;
