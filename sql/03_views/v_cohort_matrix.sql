-- ============================================================
-- v_cohort_matrix : コホート定着率マトリクス（ダッシュボード用）
-- ------------------------------------------------------------
-- 粒度   : 1行 = 獲得月 × 経過月数
-- 依存   : v_cohort_recent, v_config
--
-- 設計メモ
--   - GENERATE_ARRAY でマス目を生成し LEFT JOIN することで、「経過済み
--     だが活動がゼロだった月」を 0% として明示的に補完している。
--     行が存在しないことと値が0であることは意味が異なるため、
--     集計の前段で区別している。
--   - grid の生成条件を「< 当月」としているのは、未到来の月を行ごと
--     発生させないため。これを「<= 当月」にすると、まだ到来していない
--     月まで 0% として埋められ、直近コホートが壊滅しているように見える。
--     あわせて進行中の月も除外され、月の途中の実績が1ヶ月分として
--     扱われることを防いでいる。
--   - BI側では month_index = 0 を除外して表示する。0ヶ月目の定着率は
--     定義上必ず100%で情報量がなく、含めるとヒートマップの色スケールが
--     0〜100に引き伸ばされて実データの濃淡が潰れるため。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_cohort_matrix` AS
WITH config AS (
  SELECT analysis_date FROM `ec-customer-analytics.ec_mart.v_config`
),
cohorts AS (
  SELECT DISTINCT cohort_month, cohort_users
  FROM `ec-customer-analytics.ec_mart.v_cohort_recent`
),
grid AS (
  SELECT c.cohort_month, c.cohort_users, m AS month_index
  FROM cohorts AS c
  CROSS JOIN UNNEST(GENERATE_ARRAY(0, 12)) AS m
  CROSS JOIN config AS cfg
  WHERE DATE_ADD(c.cohort_month, INTERVAL m MONTH) < DATE_TRUNC(cfg.analysis_date, MONTH)
)
SELECT
  g.cohort_month,
  g.cohort_users,
  g.month_index,
  IFNULL(mc.active_users,   0) AS active_users,
  IFNULL(mc.retention_rate, 0) AS retention_rate
FROM grid AS g
LEFT JOIN `ec-customer-analytics.ec_mart.v_cohort_recent` AS mc
  ON  g.cohort_month = mc.cohort_month
  AND g.month_index  = mc.month_index;
