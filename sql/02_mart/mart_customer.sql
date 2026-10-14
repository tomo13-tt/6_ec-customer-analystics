-- ============================================================
-- mart_customer : 顧客サマリ
-- ------------------------------------------------------------
-- 粒度   : 1行 = 顧客1人
-- 主キー : user_id
-- 依存   : mart_order_items, thelook_ecommerce.users, v_config
--
-- 設計メモ
--   - users を起点に LEFT JOIN している。未購入者を落とすとCVRや
--     購入転換率が計算できなくなるため、購買実績のない顧客も1行として残す。
--     未購入者の実績列は IFNULL(..., 0) で0埋めし、NULLと0の混在を避けている。
--   - recency_days は「実行日」ではなく v_config の分析基準日から算出する。
--     実行タイミングによってRFMスコアが変動することを防ぐため。
--   - CLUSTER BY user_id。下流のRFM・コホート・LTVがいずれも user_id で
--     結合するため、クラスタリングでスキャン量を抑える。
--   - customer_type は注文回数による区分。RFMのスコアとは別に、
--     単発購入とリピーターの比率を素早く見るための粗い分類として持たせている。
-- ============================================================
CREATE OR REPLACE TABLE `ec-customer-analytics.ec_mart.mart_customer`
CLUSTER BY user_id
AS
WITH config AS (
  SELECT analysis_date FROM `ec-customer-analytics.ec_mart.v_config`
),
-- 顧客ごとの購買サマリを作る
purchase_summary AS (
  SELECT
    user_id,
    MIN(order_date)                  AS first_order_date,
    MAX(order_date)                  AS last_order_date,
    COUNT(DISTINCT order_id)         AS order_count,
    COUNT(*)                         AS item_count,
    ROUND(SUM(sale_price), 2)        AS total_revenue,
    ROUND(SUM(gross_profit), 2)      AS total_profit,
    ROUND(AVG(sale_price), 2)        AS avg_item_price,
    COUNT(DISTINCT product_category) AS category_variety
  FROM `ec-customer-analytics.ec_mart.mart_order_items`
  GROUP BY user_id
)
SELECT
  u.id             AS user_id,
  u.age            AS user_age,
  u.gender         AS user_gender,
  u.country        AS user_country,
  u.traffic_source AS user_traffic_source,
  DATE(u.created_at) AS signup_date,

  -- 購買実績（未購入者はNULLになるのでIFNULLで0埋め）
  ps.first_order_date,
  ps.last_order_date,
  IFNULL(ps.order_count, 0)      AS order_count,
  IFNULL(ps.item_count, 0)       AS item_count,
  IFNULL(ps.total_revenue, 0)    AS total_revenue,
  IFNULL(ps.total_profit, 0)     AS total_profit,
  ps.avg_item_price,
  IFNULL(ps.category_variety, 0) AS category_variety,

  -- 派生指標
  DATE_DIFF(c.analysis_date, ps.last_order_date, DAY)          AS recency_days,
  DATE_DIFF(ps.last_order_date, ps.first_order_date, DAY)      AS customer_lifespan_days,
  DATE_TRUNC(ps.first_order_date, MONTH)                       AS cohort_month,

  -- 購買区分
  CASE
    WHEN ps.user_id IS NULL                      THEN '未購入'
    WHEN ps.order_count = 1                      THEN '単発購入'
    WHEN ps.order_count BETWEEN 2 AND 4          THEN 'リピーター'
    ELSE '優良顧客'
  END AS customer_type

FROM `bigquery-public-data.thelook_ecommerce.users` AS u
LEFT JOIN purchase_summary AS ps
  ON u.id = ps.user_id
CROSS JOIN config AS c;
