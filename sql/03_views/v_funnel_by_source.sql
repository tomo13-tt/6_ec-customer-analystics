-- ============================================================
-- v_funnel_by_source : 流入元別のファネル通過率
-- ------------------------------------------------------------
-- 粒度   : 1行 = 流入元
-- 依存   : mart_session
--
-- 設計メモ
--   - 全体のファネル（v_funnel）では「どのステップが弱いか」しか
--     分からない。流入元で切ることで「どのチャネルの、どのステップが
--     弱いか」まで特定でき、施策の宛先が決まる。
--   - 各段階の通過率に SAFE_DIVIDE を使っているのは、セグメントによっては
--     分母が0になりうるため。通常の除算は0除算でクエリ全体が失敗する。
--   - 流入元は entry_traffic_source（セッション開始時点の流入元）を
--     採用している。セッション途中で変化しうる値を使うと、
--     1セッションがどのチャネルに属するかが一意に決まらない。
--   - 率はすべて比率なので、BI側では必ず「平均」で集計する。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_funnel_by_source` AS
SELECT
  entry_traffic_source                                                AS traffic_source,
  COUNT(*)                                                            AS sessions,
  COUNTIF(reached_product)                                            AS reached_product,
  COUNTIF(reached_cart)                                               AS reached_cart,
  COUNTIF(reached_purchase)                                           AS reached_purchase,
  ROUND(COUNTIF(reached_product) * 100.0 / COUNT(*), 2)               AS product_view_rate,
  ROUND(SAFE_DIVIDE(COUNTIF(reached_cart),
                    COUNTIF(reached_product)) * 100, 2)               AS view_to_cart_rate,
  ROUND(SAFE_DIVIDE(COUNTIF(reached_purchase),
                    COUNTIF(reached_cart)) * 100, 2)                  AS cart_to_purchase_rate,
  ROUND(COUNTIF(reached_purchase) * 100.0 / COUNT(*), 2)              AS cvr
FROM `ec-customer-analytics.ec_mart.mart_session`
GROUP BY entry_traffic_source;
