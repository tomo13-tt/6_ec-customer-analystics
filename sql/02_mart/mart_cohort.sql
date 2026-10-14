-- ============================================================
-- mart_cohort : コホート定着率
-- ------------------------------------------------------------
-- 粒度   : 1行 = 獲得月 × 経過月数
-- 主キー : cohort_month + month_index
-- 依存   : mart_customer, mart_order_items
--
-- 設計メモ
--   - コホートの定義は「初回購買月」。users.created_at（登録日）ではなく
--     初回購買日を使う。登録だけして購買していない顧客を分母に含めると、
--     定着率が実態より低く算出されるため。
--   - 分母（cohort_users）は month_index = 0 の人数で固定する。各月の
--     アクティブ人数を分母にすると、定着率が常に100%になってしまう。
--   - activity を SELECT DISTINCT user_id, 活動月 で作っているのは、
--     同じ月に複数回購買した顧客を1回として数えるため。これをしないと
--     「定着した人数」ではなく「購買回数」を数えることになる。
--   - 経過月数の上限はここでは設けない。表示側の都合（直近24ヶ月など）は
--     下流のビュー（v_cohort_recent / v_cohort_matrix）で絞る。
-- ============================================================
CREATE OR REPLACE TABLE `ec-customer-analytics.ec_mart.mart_cohort` AS
WITH cohort_base AS (
  SELECT
    user_id,
    DATE_TRUNC(first_order_date, MONTH) AS cohort_month
  FROM `ec-customer-analytics.ec_mart.mart_customer`
  WHERE order_count > 0
),
activity AS (
  SELECT DISTINCT
    user_id,
    DATE_TRUNC(order_date, MONTH) AS active_month
  FROM `ec-customer-analytics.ec_mart.mart_order_items`
),
joined AS (
  SELECT
    c.cohort_month,
    a.active_month,
    DATE_DIFF(a.active_month, c.cohort_month, MONTH) AS month_index,
    a.user_id
  FROM cohort_base AS c
  INNER JOIN activity AS a
    ON c.user_id = a.user_id
),
cohort_size AS (
  SELECT
    cohort_month,
    COUNT(DISTINCT user_id) AS cohort_users
  FROM joined
  WHERE month_index = 0
  GROUP BY cohort_month
)
SELECT
  j.cohort_month,
  j.month_index,
  COUNT(DISTINCT j.user_id) AS active_users,
  s.cohort_users,
  ROUND(COUNT(DISTINCT j.user_id) * 100.0 / s.cohort_users, 1) AS retention_rate
FROM joined AS j
INNER JOIN cohort_size AS s
  ON j.cohort_month = s.cohort_month
GROUP BY j.cohort_month, j.month_index, s.cohort_users;
