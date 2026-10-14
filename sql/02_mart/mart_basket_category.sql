-- ============================================================
-- mart_basket_category : カテゴリ単位のバスケット分析
-- ------------------------------------------------------------
-- 粒度   : 1行 = カテゴリのペア（A, B）
-- 主キー : category_a + category_b
-- 依存   : mart_order_items
--
-- 設計メモ
--   - 自己結合で同一注文内のペアを作る。結合条件に
--     a.product_category < b.product_category を入れているのが要点で、
--     これ1行で「自分自身との組」と「(A,B) と (B,A) の重複」を
--     同時に除外できる。不等号ではなく等号以外の条件にすると
--     ペアが2倍になる。
--   - 先に SELECT DISTINCT で注文×カテゴリに重複排除している。
--     同じ注文で同じカテゴリの商品を2点買っても1回として数えるため。
--     これをしないと、点数の多い注文がペア数を押し上げる。
--   - lift は A→B でも B→A でも同じ値になる（対称）。confidence は
--     方向で値が変わるため、両方向を持たせている。
--   - pair_count >= 30 で出現の少ないペアを除外。support が極端に
--     小さいペアは lift が大きく振れやすく、施策の根拠にならない。
-- ============================================================
CREATE OR REPLACE TABLE `ec-customer-analytics.ec_mart.mart_basket_category` AS
WITH
-- ① 注文×カテゴリ に重複排除（同じ注文で同カテゴリを2点買っても1回と数える）
order_category AS (
  SELECT DISTINCT
    order_id,
    product_category
  FROM `ec-customer-analytics.ec_mart.mart_order_items`
  WHERE product_category IS NOT NULL
),
-- ② 全注文数（＝バスケットの総数）
total AS (
  SELECT COUNT(DISTINCT order_id) AS total_orders
  FROM order_category
),
-- ③ カテゴリごとの出現注文数
category_count AS (
  SELECT
    product_category,
    COUNT(DISTINCT order_id) AS order_count
  FROM order_category
  GROUP BY product_category
),
-- ④ ★自己結合でペアを作る
pairs AS (
  SELECT
    a.product_category AS category_a,
    b.product_category AS category_b,
    COUNT(DISTINCT a.order_id) AS pair_count
  FROM order_category AS a
  INNER JOIN order_category AS b
    ON  a.order_id = b.order_id                  -- 同じ注文の中で
    AND a.product_category < b.product_category  -- 重複と自分自身を除く
  GROUP BY category_a, category_b
)
SELECT
  p.category_a,
  p.category_b,
  p.pair_count,
  ca.order_count   AS orders_a,
  cb.order_count   AS orders_b,
  t.total_orders,

  -- support：全注文に占める割合
  ROUND(p.pair_count / t.total_orders * 100, 4) AS support_pct,

  -- confidence：A→B
  ROUND(p.pair_count / ca.order_count * 100, 2) AS confidence_AtoB,
  -- confidence：B→A
  ROUND(p.pair_count / cb.order_count * 100, 2) AS confidence_BtoA,

  -- lift（A→BでもB→Aでも同じ値になる）
  ROUND(
    (p.pair_count / ca.order_count) / (cb.order_count / t.total_orders),
    3
  ) AS lift

FROM pairs AS p
INNER JOIN category_count AS ca ON p.category_a = ca.product_category
INNER JOIN category_count AS cb ON p.category_b = cb.product_category
CROSS JOIN total AS t
WHERE p.pair_count >= 30;   -- 出現が少なすぎるペアはノイズなので除外
