-- ============================================================
-- v_cohort_recent : 直近24ヶ月の獲得コホートに限定したビュー
-- ------------------------------------------------------------
-- 粒度   : 1行 = 獲得月 × 経過月数
-- 依存   : mart_cohort, v_config
--
-- 設計メモ
--   - 表示対象の絞り込みをBI層ではなくデータ層で行うための中間ビュー。
--     全93コホートを描画すると1画面に収まらず、ダッシュボードとして
--     機能しないため、直近24ヶ月に限定している。
--   - BI側のフィルタでも同じ結果は得られるが、SQL側で絞るほうが
--     読み込むデータ量が減る。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_cohort_recent` AS
WITH config AS (
  SELECT analysis_date FROM `ec-customer-analytics.ec_mart.v_config`
)
SELECT c.*
FROM `ec-customer-analytics.ec_mart.mart_cohort` AS c
CROSS JOIN config AS cfg
WHERE c.cohort_month >= DATE_SUB(DATE_TRUNC(cfg.analysis_date, MONTH), INTERVAL 23 MONTH);
