-- ============================================================
-- mart_order_items : 分析用の注文明細（ステージング層）
-- ------------------------------------------------------------
-- 粒度   : 1行 = 注文の中の商品1点
-- 主キー : order_item_id
-- 依存   : thelook_ecommerce.order_items / products / users, v_config
--
-- 設計メモ
--   - 以降のすべての集計はこのテーブルを起点とする。売上の定義
--     （キャンセル・返品を除く）と期間の定義（基準日以前）を
--     この1箇所に閉じ込めることで、下流のクエリが同じ前提を
--     繰り返し書かずに済み、定義のずれも起きない。
--   - 金額は order_items にしか存在しない。orders は金額を持たないため、
--     売上集計には使えない。
--   - status の除外は明細単位で行う。キャンセルや返品は商品単位で
--     発生するため、注文単位で除外すると生きている明細まで落ちる。
--   - 基準日以前に絞っているのは、元データに未来日付の行が
--     含まれうるため。v_config を参照することで、実行日によって
--     集計対象が変わることを防いでいる。
--   - PARTITION BY order_date + CLUSTER BY user_id, product_category。
--     期間で絞り、顧客またはカテゴリで集約するクエリが大半を占めるため。
--   - 商品マスタ・顧客マスタは INNER JOIN。孤児レコードが0件であることを
--     事前に確認済み。
-- ============================================================
CREATE OR REPLACE TABLE `ec-customer-analytics.ec_mart.mart_order_items`
PARTITION BY order_date
CLUSTER BY user_id, product_category
AS
SELECT
  oi.id              AS order_item_id,
  oi.order_id,
  oi.user_id,
  oi.product_id,
  DATE(oi.created_at) AS order_date,
  oi.created_at       AS order_ts,
  oi.status           AS item_status,
  oi.sale_price,

  -- 商品マスタから
  p.name                           AS product_name,
  p.brand                          AS product_brand,
  p.category                       AS product_category,
  p.department                     AS product_department,
  p.cost                           AS product_cost,
  ROUND(oi.sale_price - p.cost, 2) AS gross_profit,

  -- 顧客マスタから
  u.age            AS user_age,
  u.gender         AS user_gender,
  u.country        AS user_country,
  u.traffic_source AS user_traffic_source,
  DATE(u.created_at) AS user_signup_date

FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
INNER JOIN `bigquery-public-data.thelook_ecommerce.products` AS p
  ON oi.product_id = p.id
INNER JOIN `bigquery-public-data.thelook_ecommerce.users` AS u
  ON oi.user_id = u.id
WHERE
  -- 売上の定義：キャンセル・返品を除外
  oi.status NOT IN ('Cancelled', 'Returned')
  -- 基準日以前のみ（未来データを除外）
  AND DATE(oi.created_at) <= (
    SELECT analysis_date FROM `ec-customer-analytics.ec_mart.v_config`
  );
