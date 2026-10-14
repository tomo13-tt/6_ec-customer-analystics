-- ============================================================
-- mart_basket_product : 商品単位のバスケット分析
-- ------------------------------------------------------------
-- 粒度   : 1行 = 商品のペア（A, B）
-- 主キー : product_a + product_b
-- 依存   : mart_order_items
--
-- 設計メモ
--   - カテゴリ版と同じ自己結合の手法を、商品単位に適用したもの。
--     粒度が細かいぶん強い関連（高いlift）が検出されやすい一方、
--     1ペアあたりの出現数が小さくなり、偶然の同時購入を拾いやすい。
--   - 先に top_products で注文数上位500商品に絞っている。商品は
--     約3万点あり、全件で自己結合すると組み合わせが爆発するため。
--     裾野の商品は出現数が少なく、どのみち統計的に扱えない。
--   - pair_count >= 5。カテゴリ版（30）より緩いのは、商品単位では
--     そもそも母数が小さく、30で切ると結果がほぼ残らないため。
--   - 列 product_a / product_b には商品IDではなく商品名が入る。
--     結合キーとしては product_id を使い、出力時に名前へ置き換えている。
-- ============================================================
CREATE OR REPLACE TABLE `ec-customer-analytics.ec_mart.mart_basket_product` AS
WITH
-- ① 売れ筋商品だけに絞る（上位500商品）
top_products AS (
  SELECT product_id
  FROM `ec-customer-analytics.ec_mart.mart_order_items`
  GROUP BY product_id
  ORDER BY COUNT(DISTINCT order_id) DESC
  LIMIT 500
),
order_product AS (
  SELECT DISTINCT
    oi.order_id,
    oi.product_id,
    oi.product_name
  FROM `ec-customer-analytics.ec_mart.mart_order_items` AS oi
  INNER JOIN top_products AS tp
    ON oi.product_id = tp.product_id
),
total AS (
  SELECT COUNT(DISTINCT order_id) AS total_orders FROM order_product
),
product_count AS (
  SELECT
    product_id,
    ANY_VALUE(product_name)  AS product_name,
    COUNT(DISTINCT order_id) AS order_count
  FROM order_product
  GROUP BY product_id
),
pairs AS (
  SELECT
    a.product_id AS product_a,
    b.product_id AS product_b,
    COUNT(DISTINCT a.order_id) AS pair_count
  FROM order_product AS a
  INNER JOIN order_product AS b
    ON  a.order_id = b.order_id
    AND a.product_id < b.product_id
  GROUP BY product_a, product_b
)
SELECT
  pa.product_name AS product_a,
  pb.product_name AS product_b,
  p.pair_count,
  ROUND(p.pair_count / t.total_orders * 100, 4) AS support_pct,
  ROUND(p.pair_count / pa.order_count * 100, 2) AS confidence_AtoB,
  ROUND(
    (p.pair_count / pa.order_count) / (pb.order_count / t.total_orders), 3
  ) AS lift
FROM pairs AS p
INNER JOIN product_count AS pa ON p.product_a = pa.product_id
INNER JOIN product_count AS pb ON p.product_b = pb.product_id
CROSS JOIN total AS t
WHERE p.pair_count >= 5;
