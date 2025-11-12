/* Проект - анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
*/

-- Пример фильтрации данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

WITH limits AS (
    SELECT 
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
filtered_id AS (
    SELECT id
    FROM real_estate.flats 
    WHERE total_area < (SELECT total_area_limit FROM limits)
      AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
      AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
      AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits) AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
categorized_flats AS (
select
        f.id,  -- ид квартиры
        a.days_exposition,  -- длительность размещения объявления
        c.city,  -- город
        CASE WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург' ELSE 'ЛенОбл' END AS region,  --регион
        CASE 
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN 'Месяц'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'Квартал'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'Полгода'
            ELSE 'Больше полугода' 
        END AS exposition_category,  --срок активности
        f.total_area,  -- общая площадь
        f.rooms,  -- кол-во комнат
        f.balcony,  -- кол-во балконов
        a.last_price / NULLIF(f.total_area, 0) AS price_per_sqm,  -- цена за кв м
        CASE WHEN f.is_apartment = 1 THEN 'апартаменты' ELSE 'квартира' END AS apartment_category  -- тип жилья
    FROM real_estate.flats f
    JOIN real_estate.advertisement a ON f.id = a.id  -- соединяю с объявлениями
    JOIN real_estate.city c ON f.city_id = c.city_id  -- соединяю с городами
    WHERE f.id IN (SELECT id FROM filtered_id)  -- фильтрация по выбросам
      AND EXTRACT(YEAR FROM a.first_day_exposition) NOT IN (2014, 2019)  -- убираю неполные годы
)
SELECT
    region,  -- СПб или ЛенОбл
    exposition_category,  -- срок активности
    apartment_category,  -- квартира или апартаменты
    COUNT(*) AS total_ads,  -- общее кол-во объявлений
    ROUND(AVG(price_per_sqm)::numeric, 0) AS avg_price_per_sqm,  -- средняя цена за кв м
    ROUND(AVG(total_area)::numeric, 2) AS avg_total_area,  -- средняя площадь
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS median_rooms,  -- медианное комнат
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS median_balcony  -- медианное балконов
FROM categorized_flats
GROUP BY region, exposition_category, apartment_category
ORDER BY region, exposition_category, apartment_category;



-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

WITH limits AS (
    SELECT 
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
filtered_id AS (
    SELECT id
    FROM real_estate.flats 
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (
            (ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
             AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
             OR ceiling_height IS NULL)
),
-- СТЕ для даты снятия с публикации
flats_with_dates AS (
    SELECT
        f.id,
        a.first_day_exposition,  -- дата публикации
        a.days_exposition,   -- сколько дней объявление было активно
        f.total_area,  -- площадь
        a.last_price,  -- итоговая цена
        CASE
            WHEN a.days_exposition > 0 THEN a.first_day_exposition + (a.days_exposition * INTERVAL '1 day')
            ELSE NULL
        END AS last_day_exposition  -- дата снятия с публикации
    FROM real_estate.flats f
    JOIN real_estate.advertisement a ON f.id = a.id
    WHERE f.id IN (SELECT id FROM filtered_id)   -- фильтрую по выбросам
),
-- данные по месяцам публикации
published_by_month AS (
    SELECT
        EXTRACT(MONTH FROM first_day_exposition) AS month_num,  -- номер месяца публикации
        TO_CHAR(first_day_exposition, 'TMMonth') AS month_name, -- название месяца
        COUNT(*) AS total_published,   -- сколько объявлений опубликовано
        ROUND(AVG(total_area)::numeric, 2) AS avg_area_published, -- средняя площадь опубликованных
        ROUND(AVG(last_price / total_area)::numeric, 0) AS price_per_sqm_published -- средняя цена за кв м опубликованных
    FROM flats_with_dates
    GROUP BY month_num, month_name
),
-- данные по месяцам снятия с публикации
withdrawn_by_month AS (
    SELECT
        EXTRACT(MONTH FROM last_day_exposition) AS month_num,  -- номер месяца снятия
        TO_CHAR(last_day_exposition, 'TMMonth') AS month_name,  -- название месяца
        COUNT(*) AS total_withdrawn,    -- сколько объявлений снято
        ROUND(AVG(total_area)::numeric, 2) AS avg_area_withdrawn, -- средняя площадь снятых
        ROUND(AVG(last_price / total_area)::numeric, 0) AS price_per_sqm_withdrawn -- средняя цена за кв м снятых
    FROM flats_with_dates
    WHERE last_day_exposition IS NOT NULL   -- исключаю NULL (актуальные объявления)
    GROUP BY month_num, month_name
),
-- считаю общее кол-во объявлений и снятых
total_counts AS (
    SELECT 
        COUNT(*) AS total_ads,   -- всего объявлений
        COUNT(*) FILTER (WHERE last_day_exposition IS NOT NULL) AS total_withdrawn_ads -- всего снятых
    FROM flats_with_dates
)
-- соединяю публикации и снятия по месяцу
SELECT
    p.month_name AS month_name,   -- название месяца
    p.total_published,   -- опубликовано в этом месяце
    w.total_withdrawn,  -- снято в этом месяце
    p.avg_area_published,   -- средняя площадь опубликованных
    p.price_per_sqm_published,  -- цена за кв м опубликованных
    w.avg_area_withdrawn,    -- средняя площадь снятых
    w.price_per_sqm_withdrawn,  -- цена за кв м снятых
    ROUND(100.0 * p.total_published / tc.total_ads, 1) AS percent_published, -- % от всех опубликованных
    ROUND(100.0 * w.total_withdrawn / tc.total_ads, 1) AS percent_withdrawn -- % от всех снятых
FROM published_by_month p
LEFT JOIN withdrawn_by_month w ON p.month_num = w.month_num  -- соединение по номеру месяца
CROSS JOIN total_counts tc  -- для вычисления %
ORDER BY p.month_num;


-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (
            (ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
             AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
            OR ceiling_height IS NULL
        )
),
flats_ads AS (
    SELECT
        f.id,
        f.total_area,
        f.rooms,
        f.balcony,
        f.ceiling_height,
        f.city_id,
        c.city,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        a.last_price / NULLIF(f.total_area, 0) AS price_per_sqm,
        CASE 
            WHEN a.days_exposition IS NOT NULL THEN 1 
            ELSE 0 
        END AS is_off,
        CASE 
            WHEN c.city = 'Санкт-Петербург' THEN 'СПб' 
            ELSE 'ЛенОбл' 
        END AS region
    FROM real_estate.flats f
    JOIN real_estate.advertisement a ON f.id = a.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    WHERE f.id IN (SELECT id FROM filtered_id)
      AND EXTRACT(YEAR FROM a.first_day_exposition) NOT IN (2014, 2019)
      AND c.city <> 'Санкт-Петербург'
),
filtered_cities AS (
    SELECT city
    FROM flats_ads
    WHERE region = 'ЛенОбл'
    GROUP BY city
    HAVING COUNT(*) > 50 
    /* порог 50 объявлений позволит исключить населённые пункты с малым количеством данных, 
где статистика может быть нерепрезентативной (например, один-два аномальных случая сильно искажают средние значения).
в то же время этот порог достаточно низкий, чтобы не отсеять слишком много населённых пунктов, 
которые могли бы быть интересны бизнесу для анализа спроса и предложения.*/
)
SELECT 
    f.city,
    COUNT(*) AS total_ads,  -- всего объявлений
    ROUND(AVG(price_per_sqm)::numeric, 0) AS avg_price_per_sqm, -- средняя цена за кв м
    ROUND(AVG(total_area)::numeric, 2) AS avg_total_area, -- средняя площадь
    ROUND(AVG(days_exposition)::numeric, 0) AS avg_days_exposition, -- средняя длительность публикации
    ROUND(100.0 * SUM(is_off)::numeric / COUNT(*), 1) AS percent_removed -- доля снятых с публикации
FROM flats_ads f
WHERE f.city IN (SELECT city FROM filtered_cities)
GROUP BY f.city
ORDER BY total_ads DESC;
