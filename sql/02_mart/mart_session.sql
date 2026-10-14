-- ============================================================
-- mart_session : セッション単位のサマリ
-- ------------------------------------------------------------
-- 粒度   : 1行 = セッション1件
-- 主キー : session_id
-- 依存   : mart_session_events
--
-- 設計メモ
--   - イベント粒度のログをセッション粒度に集約する層。ファネル分析は
--     「何回クリックされたか」ではなく「何セッションが到達したか」で
--     見るため、ここで粒度を揃えてから集計する。
--
--   - 到達判定は COUNTIF(...) > 0 で真偽値にしている。「そのイベントが
--     1回以上あったか」を表すため、同一セッション内で同じ行動を
--     繰り返しても二重に数えない。LOGICAL_OR でも同じ結果になる。
--
--   - 流入元はセッション最初のイベントの値を採用する。セッション途中で
--     変化しうる値なので、最初の1件に固定しないと「このセッションが
--     どのチャネルに属するか」が一意に決まらない。
--     ARRAY_AGG(... ORDER BY event_ts LIMIT 1)[SAFE_OFFSET(0)] で取得する。
--
--   - ARRAY_AGG の3つの指定はいずれも必須。
--       LIMIT 1        … 省略すると全行が配列に入りメモリを浪費する
--       IGNORE NULLS   … NULLが1つでもあると配列エラーで落ちる
--       SAFE_OFFSET(0) … 配列が空のとき添字エラーにせずNULLを返す
--     特に IGNORE NULLS の付け忘れは、データが増えたある日突然
--     エラーになるタイプの不具合になる。
--
--   - PARTITION BY session_date + CLUSTER BY user_id。
-- ============================================================
CREATE OR REPLACE TABLE `ec-customer-analytics.ec_mart.mart_session`
PARTITION BY session_date
CLUSTER BY user_id
AS
SELECT
  my_session_id          AS session_id,
  user_id,
  DATE(MIN(event_ts))    AS session_date,
  MIN(event_ts)          AS session_start,
  MAX(event_ts)          AS session_end,
  TIMESTAMP_DIFF(MAX(event_ts), MIN(event_ts), SECOND) AS duration_sec,
  COUNT(*)               AS event_count,

  -- 流入元（セッション最初のイベントのもの）
  ARRAY_AGG(traffic_source IGNORE NULLS ORDER BY event_ts LIMIT 1)[SAFE_OFFSET(0)] AS entry_traffic_source,
  ARRAY_AGG(uri            IGNORE NULLS ORDER BY event_ts LIMIT 1)[SAFE_OFFSET(0)] AS entry_uri,

  -- ★ファネルの各段階に到達したか
  COUNTIF(event_type = 'home')       > 0 AS reached_home,
  COUNTIF(event_type = 'department') > 0 AS reached_department,
  COUNTIF(event_type = 'product')    > 0 AS reached_product,
  COUNTIF(event_type = 'cart')       > 0 AS reached_cart,
  COUNTIF(event_type = 'purchase')   > 0 AS reached_purchase

FROM `ec-customer-analytics.ec_mart.mart_session_events`
GROUP BY my_session_id, user_id;
