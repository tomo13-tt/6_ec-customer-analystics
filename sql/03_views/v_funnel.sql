-- ============================================================
-- v_funnel : セッション単位のファネル（全流入元）
-- ------------------------------------------------------------
-- 粒度   : 1行 = ファネルのステップ（5段階）
-- 依存   : mart_session
--
-- 設計メモ
--   - COUNTIF で各ステップへの到達セッション数を横持ちで数えたあと、
--     UNION ALL で縦持ちに変換している。UNPIVOT でも同じ結果になるが、
--     ステップ番号と日本語のステップ名を同時に付与したいため
--     UNION ALL を採用した。
--   - 「全体通過率」は FIRST_VALUE、「直前からの通過率」は LAG で算出。
--     前者は最初のステップを100%とした絶対的な残存率、後者は直前の
--     ステップからの相対的な通過率で、改善の優先順位は後者で決まる。
--   - 通過率・離脱率はいずれも比率なので、BI側では必ず「平均」で
--     集計する。また並び替えは step_no の昇順で固定する。
--     セッション数の降順にするとファネルの順序が崩れて読めなくなる。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_funnel` AS
WITH counts AS (
  SELECT
    COUNT(*)                    AS step0_session,
    COUNTIF(reached_department) AS step1_department,
    COUNTIF(reached_product)    AS step2_product,
    COUNTIF(reached_cart)       AS step3_cart,
    COUNTIF(reached_purchase)   AS step4_purchase
  FROM `ec-customer-analytics.ec_mart.mart_session`
),
-- 縦持ちに変換
unpivoted AS (
  SELECT 1 AS step_no, 'セッション開始' AS step_name, step0_session   AS sessions FROM counts
  UNION ALL SELECT 2, 'カテゴリ閲覧',    step1_department FROM counts
  UNION ALL SELECT 3, '商品詳細閲覧',    step2_product    FROM counts
  UNION ALL SELECT 4, 'カート投入',      step3_cart       FROM counts
  UNION ALL SELECT 5, '購入完了',        step4_purchase   FROM counts
)
SELECT
  step_no,
  step_name,
  sessions,

  -- 最初のステップを100%とした通過率
  ROUND(sessions * 100.0
        / FIRST_VALUE(sessions) OVER (ORDER BY step_no), 2) AS overall_rate,

  -- 直前のステップからの通過率
  ROUND(sessions * 100.0
        / LAG(sessions) OVER (ORDER BY step_no), 2)         AS step_rate,

  -- 直前のステップからの離脱率
  ROUND(100 - sessions * 100.0
        / LAG(sessions) OVER (ORDER BY step_no), 2)         AS drop_rate,

  -- 離脱した実数
  LAG(sessions) OVER (ORDER BY step_no) - sessions          AS dropped_sessions
FROM unpivoted;
