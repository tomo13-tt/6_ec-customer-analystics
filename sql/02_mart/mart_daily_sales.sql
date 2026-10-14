-- ============================================================
-- mart_daily_sales : 日次売上サマリ
-- ------------------------------------------------------------
-- 粒度   : 1行 = 1日
-- 主キー : order_date
-- 依存   : mart_order_items, v_config
--
-- 設計メモ
--   - GENERATE_DATE_ARRAY で期間内の全日付を生成し、実績を LEFT JOIN して
--     いる。注文のない日を行ごと欠落させると、下流の移動平均（ROWS BETWEEN）
--     や前年同日比（LAG 365）の窓が日数ではなく行数でずれるため。
--     売上ゼロの日は 0 として明示的に埋める。
--   - 終端を v_config の分析基準日に固定している。CURRENT_DATE を直接使うと、
--     実行日によってテーブルの行数が変わり、前年比の参照先がずれる。
--   - PARTITION BY order_date。日付で絞り込むクエリが大半なので、
--     パーティションプルーニングでスキャン量を抑える。
--   - 年・月・曜日などの日付属性を列として持たせているのは、BI側で
--     同じ計算を繰り返さないため。曜日は数値（並び替え用）と文字列
--     （表示用）の両方を持つ。
-- ============================================================
CREATE OR REPLACE TABLE `ec-customer-analytics.ec_mart.mart_daily_sales`
PARTITION BY order_date
AS
WITH config AS (
  SELECT analysis_date FROM `ec-customer-analytics.ec_mart.v_config`
),
-- 実績の日次集計
actual AS (
  SELECT
    order_date,
    COUNT(DISTINCT order_id)     AS order_count,
    COUNT(DISTINCT user_id)      AS buyer_count,
    COUNT(*)                     AS item_count,
    ROUND(SUM(sale_price), 2)    AS revenue,
    ROUND(SUM(gross_profit), 2)  AS profit
  FROM `ec-customer-analytics.ec_mart.mart_order_items`
  GROUP BY order_date
),
-- 期間内の全日付を生成（売上ゼロの日を作るため）
calendar AS (
  SELECT day AS order_date
  FROM UNNEST(
    GENERATE_DATE_ARRAY(
      (SELECT MIN(order_date) FROM actual),
      (SELECT analysis_date FROM config),
      INTERVAL 1 DAY
    )
  ) AS day
)
SELECT
  c.order_date,
  IFNULL(a.order_count, 0) AS order_count,
  IFNULL(a.buyer_count, 0) AS buyer_count,
  IFNULL(a.item_count, 0)  AS item_count,
  IFNULL(a.revenue, 0)     AS revenue,
  IFNULL(a.profit, 0)      AS profit,

  -- 日付の属性（BIでのフィルタ・並び替え用）
  EXTRACT(YEAR      FROM c.order_date)      AS year,
  EXTRACT(MONTH     FROM c.order_date)      AS month,
  EXTRACT(DAY       FROM c.order_date)      AS day_of_month,
  EXTRACT(DAYOFWEEK FROM c.order_date)      AS day_of_week_num,
  FORMAT_DATE('%a', c.order_date)           AS day_of_week,
  DATE_TRUNC(c.order_date, MONTH)           AS month_start,
  DATE_TRUNC(c.order_date, WEEK(MONDAY))    AS week_start

FROM calendar AS c
LEFT JOIN actual AS a
  ON c.order_date = a.order_date;
