-- ============================================================
-- v_ltv_curve : 流入元別のLTVカーブ（ダッシュボード用）
-- ------------------------------------------------------------
-- 粒度   : 1行 = 流入元 × 経過日数マイルストーン
-- 依存   : mart_ltv
--
-- 設計メモ
--   - target_users >= 30 で、サンプル数が少なすぎるセグメントを除外して
--     いる。母数が小さいと平均が不安定になり、チャネル間の比較が
--     成立しないため。閾値30は中心極限定理の目安として一般的な水準。
--   - 平均と中央値の両方を持たせている。LTVは一部の高額顧客によって
--     分布が右に歪むため、平均のみでは実態を過大評価する。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_ltv_curve` AS
SELECT
  traffic_source,
  days_elapsed,
  avg_ltv,
  median_ltv,
  target_users
FROM `ec-customer-analytics.ec_mart.mart_ltv`
WHERE target_users >= 30;
