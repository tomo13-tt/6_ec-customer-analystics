-- ============================================================
-- mart_rfm : RFMスコアとセグメント
-- ------------------------------------------------------------
-- 粒度   : 1行 = 顧客1人（購買実績のある顧客のみ）
-- 主キー : user_id
-- 依存   : mart_customer
--
-- 設計メモ
--   - スコアは NTILE(5) による5分位。絶対値の閾値を決め打ちしないのは、
--     データの増減や季節変動でセグメントの人数が偏らないようにするため。
--     相対順位で切れば、各セグメントの構成比は概ね一定に保たれる。
--   - ORDER BY の向きに注意。recency_days は「小さいほど良い」ので
--     DESC で並べて直近の顧客に5が付く。order_count と total_revenue は
--     「大きいほど良い」ので ASC で並べて多い顧客に5が付く。
--     向きを揃えると意味が反転するため、列ごとに指定している。
--   - 未購入者（order_count = 0）は除外している。recency_days が
--     NULL になり、NTILE が意味を持たないため。未購入者を含めた
--     全体像は mart_customer 側で見る。
--   - rfm_code（"543" のような3桁の文字列）は125通りの細かい分類、
--     rfm_segment はそれを5つに集約した実務用の分類。細かい分類は
--     分析時の深掘りに、粗い分類はダッシュボードの表示に使い分ける。
--   - セグメントの判定は r_score（離反の兆候）を主軸に、f_score と
--     m_score の平均（fm_score）を従にしている。売上規模が大きくても
--     直近の購買が途絶えていれば「離反危険」として最優先で拾う設計。
-- ============================================================
CREATE OR REPLACE TABLE `ec-customer-analytics.ec_mart.mart_rfm`
CLUSTER BY user_id
AS
WITH base AS (
  SELECT
    user_id,
    user_age,
    user_gender,
    user_country,
    user_traffic_source,
    recency_days,
    order_count,
    total_revenue,
    first_order_date,
    last_order_date
  FROM `ec-customer-analytics.ec_mart.mart_customer`
  WHERE order_count > 0
),
scored AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY recency_days  DESC) AS r_score,
    NTILE(5) OVER (ORDER BY order_count   ASC)  AS f_score,
    NTILE(5) OVER (ORDER BY total_revenue ASC)  AS m_score
  FROM base
)
SELECT
  *,
  CONCAT(
    CAST(r_score AS STRING),
    CAST(f_score AS STRING),
    CAST(m_score AS STRING)
  ) AS rfm_code,
  ROUND((f_score + m_score) / 2, 1) AS fm_score,
  CASE
    WHEN r_score >= 4 AND ((f_score + m_score) / 2) >= 4 THEN '① 優良顧客'
    WHEN r_score >= 4 AND ((f_score + m_score) / 2) <  4 THEN '② 新規・育成中'
    WHEN r_score =  3                                    THEN '③ 安定層'
    WHEN r_score <= 2 AND ((f_score + m_score) / 2) >= 4 THEN '④ 離反危険（重要）'
    ELSE '⑤ 休眠'
  END AS rfm_segment
FROM scored;
