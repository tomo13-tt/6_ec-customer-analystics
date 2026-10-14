-- ============================================================
-- mart_session_events : 行動ログへのセッションID付与（gaps-and-islands）
-- ------------------------------------------------------------
-- 粒度   : 1行 = イベント1件
-- 主キー : event_id
-- 依存   : thelook_ecommerce.events, v_config
--
-- 設計メモ
--   - 「30分以上の無操作で別セッションとみなす」という定義を自前で実装
--     している。元データには session_id が既に存在するが、実務では
--     セッション定義がログに含まれない、あるいは定義が要件と合わない
--     ことが多いため、自分で定義し、既存の session_id と照合して
--     検証できる形にしている（original_session_id として併記）。
--
--   - 実装は gaps-and-islands 法の3ステップ。
--       ステップ1：LAG で直前のイベントとの時間差を出す
--       ステップ2：時間差が閾値を超えたら「新セッション開始」フラグを1にする
--       ステップ3：フラグを累積和（SUM OVER）すると、連番がセッション番号になる
--     累積和でグループ番号を作るのがこの手法の要点で、同じ構文で
--     「連続している区間の切り出し」全般に応用できる。
--
--   - ROWS BETWEEN を明示しているのは、省略時の既定が RANGE であり、
--     同一タイムスタンプの行をまとめて扱って境界がずれるため。
--
--   - TIMESTAMP_DIFF(..., MINUTE) は切り捨てなので、`> 30` は実質
--     「31分以上」を意味する。30分ちょうどの空白は同一セッションとなる。
--
--   - 未ログイン（user_id IS NULL）のイベントは除外している。ユーザーを
--     特定できないとセッションを時系列で繋げられないため。この除外により
--     ファネルは「ログイン済みユーザーの行動」に限定される。
--
--   - session_id は user_id とセッション連番を連結して一意にしている。
--     連番だけではユーザーをまたいで衝突する。
-- ============================================================
CREATE OR REPLACE TABLE `ec-customer-analytics.ec_mart.mart_session_events`
PARTITION BY event_date
CLUSTER BY user_id
AS
WITH
-- ① 対象イベントを絞る（ログイン済みのみ・基準日以前）
base AS (
  SELECT
    e.id         AS event_id,
    e.user_id,
    e.session_id AS original_session_id,
    e.created_at AS event_ts,
    DATE(e.created_at) AS event_date,
    e.event_type,
    e.traffic_source,
    e.uri
  FROM `bigquery-public-data.thelook_ecommerce.events` AS e
  CROSS JOIN `ec-customer-analytics.ec_mart.v_config` AS cfg
  WHERE e.user_id IS NOT NULL
    AND DATE(e.created_at) <= cfg.analysis_date
),
-- ② 前のイベントとの時間差を計算（ステップ1）
with_gap AS (
  SELECT
    *,
    LAG(event_ts) OVER (PARTITION BY user_id ORDER BY event_ts) AS prev_ts,
    TIMESTAMP_DIFF(
      event_ts,
      LAG(event_ts) OVER (PARTITION BY user_id ORDER BY event_ts),
      MINUTE
    ) AS minutes_since_prev
  FROM base
),
-- ③ 新セッション開始フラグを立てる（ステップ2）
with_flag AS (
  SELECT
    *,
    CASE
      WHEN prev_ts IS NULL            THEN 1  -- そのユーザーの最初のイベント
      WHEN minutes_since_prev > 30    THEN 1  -- 30分超の空白
      ELSE 0
    END AS is_new_session
  FROM with_gap
),
-- ④ フラグを累積和してセッション番号にする（ステップ3）
with_session AS (
  SELECT
    *,
    SUM(is_new_session) OVER (
      PARTITION BY user_id
      ORDER BY event_ts
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS session_seq
  FROM with_flag
)
SELECT
  event_id,
  user_id,
  event_date,
  event_ts,
  event_type,
  traffic_source,
  uri,
  original_session_id,
  session_seq,
  -- ユーザーIDとセッション連番を組み合わせて一意なセッションIDを作る
  CONCAT(CAST(user_id AS STRING), '-', CAST(session_seq AS STRING)) AS my_session_id,
  minutes_since_prev,
  -- セッション内での何番目のイベントか
  ROW_NUMBER() OVER (
    PARTITION BY user_id, session_seq ORDER BY event_ts
  ) AS event_seq_in_session
FROM with_session;
