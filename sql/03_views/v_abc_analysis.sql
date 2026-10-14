-- ============================================================
-- v_abc_analysis : 商品のABC分析（パレート図・ランク別集計用）
-- ------------------------------------------------------------
-- 粒度   : 1行 = 商品
-- 依存   : mart_order_items
--
-- 設計メモ
--   - 累積売上構成比を SUM() OVER (ORDER BY revenue DESC ROWS BETWEEN
--     UNBOUNDED PRECEDING AND CURRENT ROW) で算出し、全体合計で割って
--     いる。ウィンドウ関数だけで完結させ、自己結合や副問い合わせを
--     使わずに済ませている。
--   - ROWS を明示しているのは、省略時の既定が RANGE であり、売上が
--     同額の商品をまとめて扱って累積値がずれるため。
--   - ランクの境界は 70% / 90%。上位2〜3割の商品が売上の7割を占める
--     という前提（パレートの法則）が実データでも成立するかを
--     検証できる形にしている。
--   - BI側のディメンションには product_id を使う。product_name は
--     重複する可能性があり、重複すると行が統合されて累積構成比が壊れる。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_abc_analysis` AS
WITH product_sales AS (
  SELECT
    product_id,
    ANY_VALUE(product_name)     AS product_name,
    ANY_VALUE(product_category) AS product_category,
    ANY_VALUE(product_brand)    AS product_brand,
    ROUND(SUM(sale_price), 2)   AS revenue,
    COUNT(DISTINCT order_id)    AS order_count
  FROM `ec-customer-analytics.ec_mart.mart_order_items`
  GROUP BY product_id
),
ranked AS (
  SELECT
    *,
    -- 売上降順の順位
    ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rank_no,
    -- 累積売上構成比
    ROUND(
      SUM(revenue) OVER (ORDER BY revenue DESC
                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      * 100.0
      / SUM(revenue) OVER ()
    , 2) AS cumulative_share
  FROM product_sales
)
SELECT
  *,
  CASE
    WHEN cumulative_share <= 70 THEN 'A（主力：売上の70%）'
    WHEN cumulative_share <= 90 THEN 'B（準主力：次の20%）'
    ELSE 'C（裾野：残り10%）'
  END AS abc_rank
FROM ranked;
