-- ============================================================
-- v_segment_action : RFMセグメント別サマリーと推奨アクション
-- ------------------------------------------------------------
-- 粒度   : 1行 = RFMセグメント
-- 依存   : mart_rfm
--
-- 設計メモ
--   - 数値の解釈を閲覧者に委ねないため、セグメントごとの推奨アクションを
--     データ側の列として持たせている。ダッシュボードを「見るもの」から
--     「使うもの」にするための設計。
--   - user_share / revenue_share は SUM(...) OVER () で全体合計を取り、
--     構成比を同一クエリ内で算出している。BI側で全体合計を持たなくて
--     済むため、どのグラフに置いても値が一致する。
--   - share 系の列は比率なので、BI側では必ず「平均」で集計する。
-- ============================================================
CREATE OR REPLACE VIEW `ec-customer-analytics.ec_mart.v_segment_action` AS
SELECT
  rfm_segment,
  COUNT(*)                                                     AS user_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)           AS user_share,
  ROUND(SUM(total_revenue), 0)                                 AS total_revenue,
  ROUND(SUM(total_revenue) * 100.0
        / SUM(SUM(total_revenue)) OVER (), 1)                  AS revenue_share,
  ROUND(AVG(total_revenue), 0)                                 AS avg_revenue,
  ROUND(AVG(order_count), 1)                                   AS avg_orders,
  ROUND(AVG(recency_days), 0)                                  AS avg_recency_days,
  CASE
    WHEN rfm_segment LIKE '①%' THEN '維持：関係継続'
    WHEN rfm_segment LIKE '②%' THEN '育成：2回目購入の後押し'
    WHEN rfm_segment LIKE '③%' THEN '観察：離反の兆候を監視'
    WHEN rfm_segment LIKE '④%' THEN '最優先：離反危険。再接触'
    ELSE '静観'
  END                                                          AS recommended_action
FROM `ec-customer-analytics.ec_mart.mart_rfm`
GROUP BY rfm_segment;
