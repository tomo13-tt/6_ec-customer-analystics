# データ辞書

`ec-customer-analytics.ec_mart` に構築したテーブル・ビューの一覧。
列の正確な型は BigQuery のエクスプローラ（テーブル → スキーマタブ）が一次情報。
ここに書くのは**粒度・主キー・結合の前提・設計上の決めごと**。

---

## 0. 元データ

`bigquery-public-data.thelook_ecommerce`

| テーブル | 1行 = 何か | 主キー | メモ |
|---|---|---|---|
| `users` | 顧客1人 | `id` | `created_at` は**登録日**であって初回購買日ではない |
| `orders` | 注文1件 | `order_id` | **金額を持たない**。集計には使えない |
| `order_items` | 注文の中の商品1点 | `id` | **金額はここだけ**。分析の土台 |
| `products` | 商品1点 | `id` | `cost` があるので粗利が出せる |
| `events` | Webイベント1件 | `id` | ファネル分析の元データ |
| `inventory_items` | 在庫1点 | `id` | 今回は未使用 |
| `distribution_centers` | 配送センター1拠点 | `id` | 今回は未使用 |

**粒度の順**（細かい → 粗い）

```
order_items（明細） → orders（注文） → users（顧客）
events（イベント）  → session        → users（顧客）
```

粒度の違うテーブルを直接JOINすると行が複製される（fan-out）。
**先に集約して粒度を揃えてから結合する。**

---

## 1. ステージング層（01_staging）

| テーブル | 1行 = 何か | 主な列 |
|---|---|---|
| `mart_order_items` | 注文明細1行（商品・顧客の属性を結合済み） | `order_id`, `user_id`, `product_id`, `order_date`, `sale_price`, `cost`, `product_name`, `product_category`, `product_brand`, `traffic_source` |

**決めごと**

- `status` が `Cancelled` / `Returned` の行は**この層で除外**している。
  以降のすべての集計がこのテーブルを起点とするため、除外条件を一箇所に閉じ込められる。
- `order_items` → `products` / `users` は `INNER JOIN`。孤児レコードが0件であることを確認済み。

---

## 2. マート層（02_mart）

| テーブル | 1行 = 何か | 主キー | 依存 |
|---|---|---|---|
| `mart_customer` | 顧客1人 | `user_id` | `mart_order_items`, `users` |
| `mart_rfm` | 顧客1人（RFMスコア付き） | `user_id` | `mart_customer` |
| `mart_cohort` | 獲得月 × 経過月数 | `cohort_month` + `month_index` | `mart_customer`, `mart_order_items` |
| `mart_ltv` | 流入元 × 経過日数 | `traffic_source` + `days_elapsed` | `mart_customer`, `mart_order_items` |
| `mart_daily_sales` | 1日 | `order_date` | `mart_order_items` |
| `mart_basket_category` | カテゴリのペア | `category_a` + `category_b` | `mart_order_items` |
| `mart_basket_product` | 商品のペア | `product_a` + `product_b` | `mart_order_items` |
| `mart_session_events` | イベント1件（セッションID付与済み） | `event_id` | `events` |
| `mart_session` | セッション1件 | `session_id` | `mart_session_events` |

**決めごと**

| 項目 | 内容 | 理由 |
|---|---|---|
| 顧客サマリ | `users` から `LEFT JOIN` で作る | 未購入者を残さないとCVRが出せない |
| 日次売上 | 日付を `GENERATE_DATE_ARRAY` で生成して結合 | 注文のない日を欠落させると移動平均・前年比の窓がずれる |
| セッション | 30分無操作で区切る（自作） | 実務ではセッション定義がログに含まれない場合が多いため。既存 `session_id` とは照合して検証 |
| ペアの重複除去 | 自己結合で `a.key < b.key` | (A,B) と (B,A) の重複、および自分自身との組を同時に除外できる |

---

## 3. ビュー層（03_views）

### v_config

| 列 | 内容 |
|---|---|
| `analysis_date` | 分析の基準日 |

全ビュー・全集計が参照する。1行のみ。

### v_kpi_summary — 1行 = 1日

| 列 | 内容 | BI集計 |
|---|---|---|
| `order_date` | 日付 | ディメンション |
| `orders` / `buyers` | 注文数・購入者数 | 合計 |
| `revenue` / `profit` | 売上・粗利 | 合計 |
| `avg_order_value` | 平均注文単価 | 平均 |
| `revenue_ma7` / `revenue_ma28` | 7日・28日移動平均 | 平均 |
| `revenue_ly` | 前年同日の売上 | 合計 |
| `yoy_percent` | 前年同日比(%) | 平均 |

### v_rfm_heatmap — 1行 = R軸 × F軸

| 列 | 内容 | BI集計 |
|---|---|---|
| `r_score` / `f_score` | RFMスコア（1〜5） | ディメンション（集計なし） |
| `user_count` | 人数 | 合計 |
| `total_revenue` / `avg_revenue` | 売上合計・平均 | 合計 / 平均 |
| `avg_recency_days` | 平均経過日数 | 平均 |

### v_segment_action — 1行 = RFMセグメント

| 列 | 内容 | BI集計 |
|---|---|---|
| `rfm_segment` | セグメント名 | ディメンション |
| `recommended_action` | 推奨アクション | ディメンション |
| `user_count` / `user_share` | 人数・人数構成比(%) | 合計 / 平均 |
| `total_revenue` / `revenue_share` | 売上・売上構成比(%) | 合計 / 平均 |
| `avg_revenue` / `avg_orders` / `avg_recency_days` | 平均値 | 平均 |

### v_cohort_recent — 1行 = 獲得月 × 経過月数

`mart_cohort` を直近24ヶ月の獲得コホートに限定したもの。列構成は `mart_cohort` と同じ。

### v_cohort_matrix — 1行 = 獲得月 × 経過月数

| 列 | 内容 | BI集計 |
|---|---|---|
| `cohort_month` | 獲得月 | ディメンション |
| `cohort_users` | コホート人数（分母） | 合計 |
| `month_index` | 経過月数 | ディメンション（集計なし） |
| `active_users` | 購買のあった人数 | 合計 |
| `retention_rate` | 定着率(%) | 平均 |

未到来の月は**行そのものが存在しない**。経過済みで購買ゼロの月は `0` が入る。

### v_cohort_avg — 1行 = 経過月数

| 列 | 内容 | BI集計 |
|---|---|---|
| `month_index` | 経過月数（0〜12） | ディメンション（集計なし） |
| `target_cohorts` | 対象コホート数 | 合計 |
| `simple_avg_retention` | 単純平均の定着率(%) | 平均 |
| `weighted_avg_retention` | 加重平均の定着率(%) | 平均 |

### v_cohort_revenue — 1行 = 獲得月 × 経過月数

| 列 | 内容 | BI集計 |
|---|---|---|
| `cohort_month` / `month_index` | 獲得月・経過月数 | ディメンション |
| `active_users` / `revenue` | 人数・売上 | 合計 |
| `arpu` | 1人あたり売上 | 平均 |

### v_ltv_curve — 1行 = 流入元 × 経過日数

| 列 | 内容 | BI集計 |
|---|---|---|
| `traffic_source` | 流入元 | ディメンション |
| `days_elapsed` | 経過日数（30/60/90/180/365） | ディメンション（集計なし） |
| `avg_ltv` / `median_ltv` | 平均LTV・中央値LTV | 平均 |
| `target_users` | 対象顧客数 | 合計 |

### v_abc_analysis — 1行 = 商品

| 列 | 内容 | BI集計 |
|---|---|---|
| `product_id` | 商品ID | ディメンション（集計なし） |
| `product_name` / `product_category` / `product_brand` | 商品属性 | ディメンション |
| `revenue` / `order_count` | 売上・注文数 | 合計 |
| `rank_no` | 売上降順の順位 | ディメンション（集計なし） |
| `cumulative_share` | 累積構成比(%) | 平均 |
| `abc_rank` | ABCランク | ディメンション |

### v_funnel — 1行 = ファネルのステップ

| 列 | 内容 | BI集計 |
|---|---|---|
| `step_no` | ステップ番号（1〜5） | ディメンション（集計なし）／**並び替えに使う** |
| `step_name` | ステップ名 | ディメンション |
| `sessions` | 到達セッション数 | 合計 |
| `overall_rate` | 全体通過率(%) | 平均 |
| `step_rate` | 直前からの通過率(%) | 平均 |
| `drop_rate` | 離脱率(%) | 平均 |
| `dropped_sessions` | 離脱セッション数 | 合計 |

### v_funnel_by_source — 1行 = 流入元

| 列 | 内容 | BI集計 |
|---|---|---|
| `traffic_source` | 流入元 | ディメンション |
| `sessions` | セッション数 | 合計 |
| `reached_product` / `reached_cart` / `reached_purchase` | 各段階の到達数 | 合計 |
| `product_view_rate` / `view_to_cart_rate` / `cart_to_purchase_rate` / `cvr` | 各段階の通過率(%) | 平均 |

---

## 4. 命名規則

| 接頭辞 | 意味 |
|---|---|
| `mart_` | 物理テーブル。データを保持する |
| `v_` | ビュー。SQLの定義のみを保持し、参照時に毎回実行される |

列名はすべて英数字とアンダースコア。BigQuery自体は日本語の列名を受け付けるが、
Looker Studio が受け付けないため、下流のツールの制約に合わせている。
日本語の表示名は Looker Studio のデータソース側で設定する。

---

## 5. スキーマを確認するクエリ

```sql
-- データセット内の全テーブル・全列（課金0バイト）
SELECT
  table_name,
  COUNT(*) AS n_cols,
  STRING_AGG(column_name, ', ' ORDER BY ordinal_position) AS columns
FROM `ec-customer-analytics.ec_mart.INFORMATION_SCHEMA.COLUMNS`
GROUP BY table_name
ORDER BY table_name;
```

```sql
-- 非ASCII（日本語）の列名が残っていないかの確認
SELECT table_name, column_name
FROM `ec-customer-analytics.ec_mart.INFORMATION_SCHEMA.COLUMNS`
WHERE REGEXP_CONTAINS(column_name, r'[^\x00-\x7F]')
ORDER BY table_name;
```
