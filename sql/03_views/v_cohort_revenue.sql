-- ============================================================
-- v_cohort_revenue : コホート別の売上と1人あたり売上（ARPU）
-- ------------------------------------------------------------
-- 粒度   : 1行 = 獲得月 × 経過月数
-- 依存   : mart_customer, mart_order_items
--
-- 設計メモ
--   - 定着率（人数ベース）だけでは、残った顧客がいくら使っているかが
--     分からない。人数が減っても1人あたり売上が伸びていれば、
--     コホートとしての価値は維持されている。その判断材料として
--     ARPU を併せて算出している。
--   - cohort_base は order_count > 0 の顧客に限定している。未購入者を
--     含めると獲得月が定義できないため。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_cohort_revenue` AS
WITH cohort_base AS (
  SELECT
    user_id,
    DATE_TRUNC(first_order_date, MONTH) AS cohort_month
  FROM `ec-customer-analytics.ec_mart.mart_customer`
  WHERE order_count > 0
),
monthly AS (
  SELECT
    c.cohort_month,
    DATE_DIFF(DATE_TRUNC(o.order_date, MONTH), c.cohort_month, MONTH) AS month_index,
    COUNT(DISTINCT o.user_id)   AS active_users,
    ROUND(SUM(o.sale_price), 2) AS revenue
  FROM `ec-customer-analytics.ec_mart.mart_order_items` AS o
  INNER JOIN cohort_base AS c
    ON o.user_id = c.user_id
  GROUP BY cohort_month, month_index
)
SELECT
  cohort_month,
  month_index,
  active_users,
  revenue,
  ROUND(revenue / active_users, 2) AS arpu   -- 1人あたり売上
FROM monthly
WHERE month_index BETWEEN 0 AND 12;
