-- ============================================================
-- v_rfm_heatmap : RFMスコアの交差集計（ヒートマップ用）
-- ------------------------------------------------------------
-- 粒度   : 1行 = R軸スコア × F軸スコア
-- 依存   : mart_rfm
--
-- 設計メモ
--   - R軸とF軸の2次元で顧客を分布させ、どの象限に人数が偏っているかを
--     見るためのビュー。金額（M軸）は指標として併せて持たせている。
--   - BI側では R軸を降順に並べ、左上が優良顧客（直近かつ高頻度）に
--     なる向きで表示する。
--   - r_score / f_score は数値だがディメンションとして使うため、
--     BI側では集計を「なし」に設定する。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_rfm_heatmap` AS
SELECT
  r_score,
  f_score,
  COUNT(*)                     AS user_count,
  ROUND(SUM(total_revenue), 0) AS total_revenue,
  ROUND(AVG(total_revenue), 0) AS avg_revenue,
  ROUND(AVG(recency_days), 0)  AS avg_recency_days
FROM `ec-customer-analytics.ec_mart.mart_rfm`
GROUP BY r_score, f_score;
