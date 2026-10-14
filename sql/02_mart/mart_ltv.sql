-- ============================================================
-- mart_ltv : 流入元別のLTVカーブ
-- ------------------------------------------------------------
-- 粒度   : 1行 = 流入元 × 経過日数マイルストーン
-- 主キー : traffic_source + days_elapsed
-- 依存   : mart_order_items, mart_customer, v_config
--
-- 設計メモ
--   - 累積売上は SUM() OVER (PARTITION BY user_id ORDER BY order_date
--     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) で算出する。
--     ROWS を明示しているのは、省略時の既定が RANGE であり、同日に
--     複数の注文がある顧客で累積値がずれるため。
--   - マイルストーン（30/60/90/180/365日）は CROSS JOIN UNNEST で
--     その場で生成している。評価軸のためだけにマスタテーブルを作らない。
--   - ★最重要：DATE_ADD(first_order_date, INTERVAL day DAY) <= 分析基準日
--     の条件で、「そのマイルストーンが実際に経過している顧客のみ」に
--     絞っている。これがないと、最近獲得した顧客の365日LTVが0円として
--     平均に混入し、伸びているチャネルほどLTVが低く見えるという
--     逆の結論になる。数字自体は出てしまうため気づきにくい。
--   - 平均と中央値を併記する。LTVは一部の高額顧客によって分布が右に
--     歪むため、平均のみでは実態を過大評価する。
-- ============================================================
CREATE OR REPLACE TABLE `ec-customer-analytics.ec_mart.mart_ltv` AS
WITH config AS (
  SELECT analysis_date FROM `ec-customer-analytics.ec_mart.v_config`
),
-- ① 顧客 × 日付で売上を集約
user_daily AS (
  SELECT
    o.user_id,
    o.order_date,
    c.first_order_date,
    c.user_traffic_source,
    DATE_DIFF(o.order_date, c.first_order_date, DAY) AS days_since_first,
    SUM(o.sale_price) AS daily_revenue
  FROM `ec-customer-analytics.ec_mart.mart_order_items` AS o
  INNER JOIN `ec-customer-analytics.ec_mart.mart_customer` AS c
    ON o.user_id = c.user_id
  GROUP BY o.user_id, o.order_date, c.first_order_date, c.user_traffic_source
),
-- ② 顧客ごとに累積売上を積み上げる
cumulative AS (
  SELECT
    user_id,
    user_traffic_source,
    first_order_date,
    order_date,
    days_since_first,
    daily_revenue,
    SUM(daily_revenue) OVER (
      PARTITION BY user_id
      ORDER BY order_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue
  FROM user_daily
),
-- ③ 評価するマイルストーン（経過日数）を定義
milestones AS (
  SELECT day FROM UNNEST([30, 60, 90, 180, 365]) AS day
),
-- ④ 各マイルストーン時点での累積額を顧客ごとに確定
user_ltv AS (
  SELECT
    c.user_id,
    c.user_traffic_source,
    m.day AS milestone_day,
    MAX(c.cumulative_revenue) AS ltv_at_milestone
  FROM cumulative AS c
  CROSS JOIN milestones AS m
  CROSS JOIN config AS cfg
  WHERE c.days_since_first <= m.day
    -- ★そのマイルストーンまでの期間が実際に経過している顧客のみ
    AND DATE_ADD(c.first_order_date, INTERVAL m.day DAY) <= cfg.analysis_date
  GROUP BY c.user_id, c.user_traffic_source, m.day
)
SELECT
  user_traffic_source                                               AS traffic_source,
  milestone_day                                                     AS days_elapsed,
  COUNT(DISTINCT user_id)                                           AS target_users,
  ROUND(AVG(ltv_at_milestone), 2)                                   AS avg_ltv,
  ROUND(APPROX_QUANTILES(ltv_at_milestone, 100)[OFFSET(50)], 2)     AS median_ltv,
  ROUND(SUM(ltv_at_milestone), 0)                                   AS total_revenue
FROM user_ltv
GROUP BY user_traffic_source, milestone_day;
