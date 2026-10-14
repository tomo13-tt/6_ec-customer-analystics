-- ============================================================
-- v_kpi_summary : 日次KPI（移動平均・前年比つき）
-- ------------------------------------------------------------
-- 粒度   : 1行 = 1日
-- 依存   : mart_daily_sales
--
-- 設計メモ
--   - 移動平均と前年同日比を計算するため、日付が歯抜けなく連続している
--     mart_daily_sales を基にしている。明細テーブルから直接集計すると
--     注文のない日が行ごと消え、ROWS BETWEEN / LAG の窓がずれる。
--   - 移動平均は RANGE ではなく ROWS を明示している。ORDER BY のみを
--     書いた場合の暗黙の既定は RANGE であり、同一日の複数行を
--     まとめて扱うため意図とずれる。
--   - avg_order_value / yoy_percent は比率なので、BI側では必ず
--     「平均」で集計する（合計すると値が壊れる）。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_kpi_summary` AS
WITH base AS (
  SELECT
    order_date,
    order_count AS orders,
    buyer_count AS buyers,
    revenue,
    profit
  FROM `ec-customer-analytics.ec_mart.mart_daily_sales`
)
SELECT
  order_date,
  orders,
  buyers,
  ROUND(revenue, 2)                      AS revenue,
  ROUND(profit, 2)                       AS profit,
  ROUND(SAFE_DIVIDE(revenue, orders), 2) AS avg_order_value,

  -- 7日移動平均
  ROUND(AVG(revenue) OVER (
    ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
  ), 2) AS revenue_ma7,

  -- 28日移動平均
  ROUND(AVG(revenue) OVER (
    ORDER BY order_date ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
  ), 2) AS revenue_ma28,

  -- 前年同日
  LAG(revenue, 365) OVER (ORDER BY order_date) AS revenue_ly,

  ROUND(SAFE_DIVIDE(
    revenue, LAG(revenue, 365) OVER (ORDER BY order_date)
  ) * 100, 1) AS yoy_percent
FROM base;
