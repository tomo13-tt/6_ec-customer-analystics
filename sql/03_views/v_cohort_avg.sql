-- ============================================================
-- v_cohort_avg : 全コホートの平均定着率カーブ
-- ------------------------------------------------------------
-- 粒度   : 1行 = 経過月数（0〜12）
-- 依存   : mart_cohort, v_config
--
-- 設計メモ
--   - 単純平均と加重平均の2通りを同時に算出している。2本が重なって
--     いれば、コホートの規模によらず定着率が安定していることの裏づけに
--     なり、以降は単純平均で語ってよいと判断できる。乖離していれば
--     小規模コホートが平均を歪めていることが分かる。
--   - マトリクス側と同様、GENERATE_ARRAY でマス目を作って LEFT JOIN し、
--     活動ゼロの月を 0% として分母に含めている。補完しない場合、その月が
--     平均の分母から消えて定着率が過大に算出される。
--   - 観測期間が未到来の月は grid の条件で除外しているため、
--     「まだ測れない月」が 0% として平均に混入することはない。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_cohort_avg` AS
WITH config AS (
  SELECT analysis_date FROM `ec-customer-analytics.ec_mart.v_config`
),
cohorts AS (
  SELECT DISTINCT cohort_month, cohort_users
  FROM `ec-customer-analytics.ec_mart.mart_cohort`
),
grid AS (
  SELECT c.cohort_month, c.cohort_users, m AS month_index
  FROM cohorts AS c
  CROSS JOIN UNNEST(GENERATE_ARRAY(0, 12)) AS m
  CROSS JOIN config AS cfg
  WHERE DATE_ADD(c.cohort_month, INTERVAL m MONTH)
        <= DATE_TRUNC(cfg.analysis_date, MONTH)
)
SELECT
  g.month_index,
  COUNT(*)                                                                AS target_cohorts,
  ROUND(AVG(IFNULL(mc.retention_rate, 0)), 2)                             AS simple_avg_retention,
  ROUND(SUM(IFNULL(mc.active_users, 0)) * 100.0 / SUM(g.cohort_users), 2) AS weighted_avg_retention
FROM grid AS g
LEFT JOIN `ec-customer-analytics.ec_mart.mart_cohort` AS mc
  ON  g.cohort_month = mc.cohort_month
  AND g.month_index  = mc.month_index
GROUP BY g.month_index;
