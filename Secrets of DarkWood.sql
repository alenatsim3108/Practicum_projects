/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Alena Tsimafeyeva
 * Дата: 14.03.2025
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков
-- 1.1. Доля платящих пользователей по всем данным:
-- Напишите ваш запрос здесь
SELECT  
COUNT (*) AS total_players, --общее кол-во игроков
SUM(fantasy.users.payer) AS paying_players, --кол-во платящих 
AVG(payer) AS paying_part --доля платящих
FROM  fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
-- Напишите ваш запрос здесь
SELECT race,
SUM(payer) AS paying_players, --кол-во платящих для расы
COUNT(*) AS total_players, -- общее кол-во игроков для расы
AVG(payer) AS paying_part -- доля платящих для расы
FROM  fantasy.users u
LEFT JOIN fantasy.race r ON r.race_id = u.race_id
GROUP BY race
ORDER BY paying_part DESC; -- сортирую по доле платящих

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
-- Напишите ваш запрос здесь
 SELECT 
COUNT(amount) AS total_amount, --количество покупок
SUM(amount) AS sum_amount, --общая сумма
MIN(amount) AS min_amount, -- минимальная покупка
MAX(amount) AS max_amount, --максимальная покупка
AVG(amount) AS avg_amount, -- среднее
PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount) AS median_amount, -- медиана
stddev (amount) AS stddev_amount -- стандартное отклонение
FROM fantasy.events;


-- 2.2: Аномальные нулевые покупки:
-- Напишите ваш запрос здесь
SELECT
COUNT(amount) AS zero_amount, --кол-во нулевых покупок
(COUNT(amount)::numeric / (SELECT COUNT(amount) FROM fantasy.events) * 100) AS zero_part --доля нулевых от всех покупок
FROM fantasy.events
WHERE amount=0; --фильтрую по нулевой сумме

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
-- Напишите ваш запрос здесь
WITH ab AS (
SELECT 
id,
CASE WHEN payer=1 THEN 'платящий'
WHEN payer=0 THEN 'неплатящий'
END AS type_of --типы игроков
FROM fantasy.users
),
player_buy AS (
SELECT 
ab.type_of,
ab.id,
COUNT (e.transaction_id) AS total_buy, --кол-во покупок на игрока
SUM (e.amount) AS total_spent --стоимость  покупок на игрока
FROM ab
LEFT JOIN fantasy.events e ON ab.id = e.id
WHERE e.amount>0  --убираю нулевые покупки
GROUP BY ab.type_of, ab.id
)
SELECT 
type_of,
COUNT (id) AS total_players, -- общее кол-во игроков в типе 
AVG(total_buy)  AS avg_buy_per_player, --среднее кол-во покупок на игрока
AVG (total_spent) AS avg_spent_per_player -- средняя сумма покупок на игрока
FROM player_buy
GROUP BY type_of;

-- 2.4: Популярные эпические предметы:
-- Напишите ваш запрос здесь

WITH item_sales as(
SELECT 
e.item_code,
i.game_items,
COUNT (e.transaction_id) AS total_sales, --общее кол-во внутриигровых продаж
COUNT (DISTINCT e.id) AS item_buyers --кол-во покупателей айтема
FROM fantasy.events e 
LEFT JOIN fantasy.items i ON e.item_code=i.item_code
WHERE e.amount>0  --убираю нулевые покупки
GROUP BY e.item_code, i.game_items
)
SELECT 
game_items,
total_sales,
ROUND(total_sales * 100 / SUM (total_sales) OVER (), 5) AS sales_part, -- доля продажи каждого предмета от всех продаж
ROUND(item_buyers * 100 / (SELECT COUNT(DISTINCT e.id) FROM fantasy.events e WHERE amount > 0 ),5) AS player_part -- доля игроков, которые хотя бы раз покупали этот предмет 
FROM item_sales
ORDER BY player_part DESC;

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
-- переписала запрос, тк сама уже запуталась в своих же комментариях и алиасах
WITH player_stats AS (
    SELECT 
    r.race_id, -- ид расы
    r.race, --раса
    COUNT(DISTINCT u.id) AS total_players, -- общее кол-во зарегистрированных игроков
    COUNT(DISTINCT CASE WHEN e.id IS NOT NULL AND e.amount > 0 THEN u.id END) AS count_paying_players, -- кол-во игроков, которые совершают внутриигровые покупки
    COUNT(DISTINCT CASE WHEN u.payer = 1 AND e.id IS NOT NULL AND e.amount > 0 THEN u.id END) AS count_total_payers, -- общее кол-во платящих игороков
    COUNT(CASE WHEN e.amount > 0 THEN e.transaction_id END) AS total_purchases, -- кол-во покупок
    SUM(e.amount) AS total_spent, -- сумма покупок
    COUNT(DISTINCT CASE WHEN e.amount > 0 THEN e.id END) AS total_buyers -- кол-во покупателей
    FROM fantasy.users u
    LEFT JOIN fantasy.events e ON u.id = e.id
    JOIN fantasy.race r ON u.race_id = r.race_id
    GROUP BY r.race_id, r.race
)
SELECT 
    race, --раса
    total_players, -- общее кол-во зарегистрированных игроков
    count_paying_players, -- кол-во игроков, которые совершают внутриигровые покупки
    count_paying_players * 1.0 / NULLIF(total_players, 0) AS paying_players_part, -- их доля от общего количества
    count_total_payers * 1.0 / NULLIF(total_buyers,0) AS total_payers_part, --доля платящих игроков от кол-ва игроков, которые совершили покупки
    total_purchases * 1.0 / NULLIF(count_paying_players, 0) AS avg_purchases_per_player, --среднее кол-во покупок на одного игрока
    total_spent * 1.0 / NULLIF(total_purchases, 0) AS avg_cost_per_purchase,  --средняя стоимость одной покупки на одного игрока
    total_spent * 1.0 / NULLIF(count_paying_players, 0) AS avg_total_spent_per_player -- средняя суммарная стоимость всех покупок на одного игрока
FROM player_stats
ORDER BY race;

-- Задача 2: Частота покупок
-- Напишите ваш запрос здесь