-- ============================================================
-- v_config : 分析の基準日
-- ------------------------------------------------------------
-- 粒度   : 1行（スカラー設定）
-- 依存   : bigquery-public-data.thelook_ecommerce.order_items
--
-- 設計メモ
--   - 全ての集計クエリがこのビューの analysis_date を参照する。
--     基準日をここ1か所に閉じ込めることで、実行タイミングによって
--     集計結果が変わることを防いでいる。
--   - LEAST(データ最大日, 実行日-1) としているのは、元データに未来日付の
--     行が含まれうること、および当日分は部分データであることの両方に
--     対応するため。どちらのケースでも安全側に倒れる。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_config` AS
SELECT
  LEAST(
    (SELECT MAX(DATE(created_at))
     FROM `bigquery-public-data.thelook_ecommerce.order_items`),
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  ) AS analysis_date;
