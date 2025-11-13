-- Расчёт DAU
SELECT 
    log_date,
    COUNT(DISTINCT user_id) AS DAU
FROM 
    analytics_events
WHERE 
    event = 'order'
    AND user_id IS NOT NULL
    AND city_id IN (SELECT city_id FROM cities WHERE city_name = 'Саранск')
    AND log_date BETWEEN '2021-05-01' AND '2021-06-30'
GROUP BY 
    log_date
ORDER BY 
    log_date ASC
LIMIT 10;

-- Расчёт Conversion Rate
SELECT log_date,
       ROUND((COUNT(DISTINCT user_id) FILTER (WHERE event = 'order')) / COUNT(DISTINCT user_id)::numeric, 2) AS CR
FROM analytics_events
JOIN cities ON analytics_events.city_id = cities.city_id
WHERE log_date BETWEEN '2021-05-01' AND '2021-06-30'
    AND city_name = 'Саранск'
GROUP BY log_date
ORDER BY log_date
LIMIT 10;

-- Расчёт среднего чека
-- Рассчитываем величину комиссии с каждого заказа, отбираем заказы по дате и городу
WITH orders AS
    (SELECT *,
            revenue * commission AS commission_revenue
     FROM analytics_events
     JOIN cities ON analytics_events.city_id = cities.city_id
     WHERE revenue IS NOT NULL
         AND log_date BETWEEN '2021-05-01' AND '2021-06-30'
         AND city_name = 'Саранск')

SELECT CAST(DATE_TRUNC('month', log_date) AS date) AS "Месяц",
       COUNT(DISTINCT order_id) AS "Количество заказов",
       ROUND(SUM(commission_revenue)::numeric, 2) AS "Сумма комиссии",
       ROUND((SUM(commission_revenue) / COUNT(DISTINCT order_id))::numeric, 2) AS "Средний чек"
FROM orders
GROUP BY "Месяц"
ORDER BY "Месяц";

 -- Расчёт LTV ресторанов
-- Рассчитываем величину комиссии с каждого заказа, отбираем заказы по дате и городу
WITH orders AS
    (SELECT analytics_events.rest_id,
            analytics_events.city_id,
            revenue * commission AS commission_revenue
     FROM analytics_events
     JOIN cities ON analytics_events.city_id = cities.city_id
     WHERE revenue IS NOT NULL
         AND log_date BETWEEN '2021-05-01' AND '2021-06-30'
         AND city_name = 'Саранск')

SELECT
    o.rest_id,
    p.chain as "Название сети",
    p.type as "Тип кухни",
    ROUND(SUM(o.commission_revenue)::numeric, 2) as LTV
FROM orders o
JOIN partners p ON o.rest_id = p.rest_id AND o.city_id = p.city_id  -- соединяем по rest_id и city_id
GROUP BY o.rest_id, p.chain, p.type
ORDER BY LTV DESC
LIMIT 3;


-- Расчёт LTV ресторанов — самые популярные блюда
-- Рассчитываем величину комиссии с каждого заказа, отбираем заказы по дате и городу
WITH orders AS
    (SELECT analytics_events.rest_id,
            analytics_events.city_id,
            analytics_events.object_id,
            revenue * commission AS commission_revenue
     FROM analytics_events
     JOIN cities ON analytics_events.city_id = cities.city_id
     WHERE revenue IS NOT NULL
         AND log_date BETWEEN '2021-05-01' AND '2021-06-30'
         AND city_name = 'Саранск'), 

-- Рассчитываем два ресторана с наибольшим LTV 
top_ltv_restaurants AS
    (SELECT orders.rest_id,
            chain,
            type,
            ROUND(SUM(commission_revenue)::numeric, 2) AS LTV
     FROM orders
     JOIN partners ON orders.rest_id = partners.rest_id AND orders.city_id = partners.city_id
     GROUP BY 1, 2, 3
     ORDER BY LTV DESC
     LIMIT 2),

top_dishes AS
    (SELECT p.chain AS "Название сети",
            d.name AS "Название блюда",
            d.spicy,
            d.fish,
            d.meat,
            ROUND(SUM(o.commission_revenue)::numeric, 2) AS LTV
     FROM orders o
     JOIN partners p ON o.rest_id = p.rest_id AND o.city_id = p.city_id
     JOIN dishes d ON o.object_id = d.object_id AND o.rest_id = d.rest_id
     JOIN top_ltv_restaurants t ON o.rest_id = t.rest_id
     GROUP BY 1, 2, 3, 4, 5
     ORDER BY LTV DESC
     LIMIT 5)

SELECT "Название сети",
       "Название блюда",
       spicy,
       fish,
       meat,
       round(LTV, 2) as LTV
FROM top_dishes
ORDER BY LTV DESC;

-- Расчёт Retention Rate
-- Рассчитываем новых пользователей по дате первого посещения продукта
WITH new_users AS
    (SELECT DISTINCT first_date,
                     user_id
     FROM analytics_events
     JOIN cities ON analytics_events.city_id = cities.city_id
     WHERE first_date BETWEEN '2021-05-01' AND '2021-06-24'
         AND city_name = 'Саранск'),

-- Рассчитываем активных пользователей по дате события
active_users AS
    (SELECT DISTINCT log_date,
                     user_id
     FROM analytics_events
     JOIN cities ON analytics_events.city_id = cities.city_id
     WHERE log_date BETWEEN '2021-05-01' AND '2021-06-30'
         AND city_name = 'Саранск'),

daily_retention AS
    (SELECT new_users.user_id,
            first_date,
            log_date::date - first_date::date AS day_since_install
     FROM new_users
     JOIN active_users ON new_users.user_id = active_users.user_id
     AND log_date >= first_date)

SELECT day_since_install,
       COUNT(DISTINCT user_id) AS retained_users,
       ROUND((1.0 * COUNT(DISTINCT user_id) / MAX(COUNT(DISTINCT user_id)) OVER (ORDER BY day_since_install))::numeric, 2) AS retention_rate
FROM daily_retention
WHERE day_since_install < 8
GROUP BY day_since_install
ORDER BY day_since_install;

-- Сравнение Retention Rate по месяцам
-- Рассчитываем новых пользователей по дате первого посещения продукта
WITH new_users AS
    (SELECT DISTINCT first_date,
                     user_id
     FROM analytics_events
     JOIN cities ON analytics_events.city_id = cities.city_id
     WHERE first_date BETWEEN '2021-05-01' AND '2021-06-24'
         AND city_name = 'Саранск'),

-- Рассчитываем активных пользователей по дате события
active_users AS
    (SELECT DISTINCT log_date,
                     user_id
     FROM analytics_events
     JOIN cities ON analytics_events.city_id = cities.city_id
     WHERE log_date BETWEEN '2021-05-01' AND '2021-06-30'
         AND city_name = 'Саранск'),

-- Соединяем таблицы с новыми и активными пользователями
daily_retention AS
    (SELECT new_users.user_id,
            first_date,
            log_date::date - first_date::date AS day_since_install
     FROM new_users
     JOIN active_users ON new_users.user_id = active_users.user_id
     AND log_date >= first_date)
     
SELECT DISTINCT CAST(DATE_TRUNC('month', first_date) AS date) AS "Месяц",
                day_since_install,
                COUNT(DISTINCT user_id) AS retained_users,
                ROUND((1.0 * COUNT(DISTINCT user_id) / MAX(COUNT(DISTINCT user_id)) OVER (PARTITION BY CAST(DATE_TRUNC('month', first_date) AS date) ORDER BY day_since_install))::numeric, 2) AS retention_rate
FROM daily_retention
WHERE day_since_install < 8
GROUP BY "Месяц", day_since_install
ORDER BY "Месяц", day_since_install;

