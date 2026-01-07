# エンジニア向け仕様書（v0.1）

## 1. プロダクト概要

### 1.1 目的
BtoB向け「匿名アセスメント」SaaSとして、以下を提供する。
- 管理者（御社）が案件（グループ）を作成
- 参加者数 N を指定して **ID+鍵（2要素）**を N 組発行
- 回答者は共通URLで ID+鍵 → 回答
- 二重回答は **送信前チェック（予約）**＋**送信時のDB制約**で拒否
- 回答が揃ったら Dify で個別/群分析し、PDFレポート生成
- レポートをメール送付（DNS認証含め）

### 1.2 非目標（PoCではやらない）
- HubSpot自動連携（ただし後付け可能なAPIは用意）
- 高度な権限体系（RBAC）・監査ログの完全版
- 多言語対応
- 重いバッチ（数千人規模）の最適化

## 2. アーキテクチャ

### 2.1 構成
- Vercel：Next.js（UI + API）
- Supabase：Postgres（データ永続化） + Storage（レポート格納）
- Dify：解析API（Workflow）
- Resend：メール送信（PDFリンク/添付）
- GitHub：コード管理 + PRレビュー + Preview Deploy

> VercelはGitHub連携で、ブランチpushごとに自動デプロイ（Preview Deployment）や本番ブランチへの自動反映が可能。

## 3. データモデル（Postgres / Supabase）

**ID被りは初期対応不要**は “全体での衝突”は許容という意味として解釈し、同一グループ内でのID+鍵の重複だけは防ぐ設計にする。

### 3.1 コアテーブル

#### groups（案件/グループ）
- id uuid PK
- org_name text
- owner_name text
- owner_email text
- requested_count int
- status enum（NEW / ISSUED / COLLECTING / ANALYZING / REPORTING / DONE / SENT）
- assessment_version text（例 v1）
- report_pdf_path text（Storage path）
- report_csv_path text（Storage path）
- created_at timestamptz

#### invitations（ID+鍵台帳）
- id uuid PK
- group_id FK
- participant_id text（ID）
- participant_key text（鍵）
- state enum（UNUSED / RESERVED / USED）
- reserved_until timestamptz
- reserved_token uuid（予約トークン）
- used_at timestamptz
- created_at timestamptz

**制約**
- UNIQUE (group_id, participant_id, participant_key)
  - グループ内での重複だけ防止（全体衝突は許容）

#### responses（回答）
- id uuid PK
- group_id FK
- invitation_id FK
- answers jsonb
- individual_result jsonb（Difyの個別出力を格納）
- created_at timestamptz

**制約**
- UNIQUE(invitation_id)
  - 1 ID+鍵（=1 invitation）につき1回答を物理的に保証

### 3.2 アセスメント体系（サービス中核）

PoCは設問固定でよいが、サービス化を見据えて “版管理できる形” にしておく。

#### assessments
- id uuid PK
- version text（例 v1）
- name text
- description text
- created_at

#### dimensions（尺度：レーダー軸）
- id uuid PK
- assessment_id FK
- key text（例 strategy, execution）
- label text（表示名）
- order int

#### questions（設問）
- id uuid PK
- assessment_id FK
- type enum（LIKERT / TEXT）
- prompt text
- dimension_id FK（LIKERTの場合の紐づけ）
- weight numeric（PoCは1固定）
- order int

PoCでは `assessment_version=v1` を groups に持たせ、質問セットは固定でOK。後で差し替え可能にしておく。

## 4. セキュリティ設計（最低限の“商品品質”）

### 4.1 シークレット管理
- Supabaseの `service_role` key は絶対にフロントに出さない（RLSをバイパスし得るため危険）
- Dify APIキー、Resend APIキーも同様に **サーバー環境変数のみ**

### 4.2 RLS（Defense in Depth）
- PoCは「サーバーAPI経由のみ」で始められるが、サービス化ではRLSを入れるのが堅い。
- SupabaseはRLSを“defense in depth”として推しており、Authと組み合わせて行レベルのアクセス制御が可能。

### 4.3 匿名回答の安全設計
- 回答者はログインなし
- ただし ID+鍵 + 予約トークンでセッション化
- 予約トークンは短寿命（例：30分）で失効

### 4.4 レート制限・Bot対策（PoC→本番）
- `/api/reserve` `/api/submit` にIP/ID単位のレート制限（Upstash等）
- 必要ならCAPTCHA（Turnstile）

## 5. 機能仕様（画面）

### 5.1 回答者導線

#### `/`（ID+鍵入力）
- 入力：ID, KEY
- 送信 → POST `/api/reserve`
- 成功 → `/survey?rt=<reservation_token>`
- 失敗 → エラーメッセージ
  - INVALID（存在しない）
  - USED（使用済み）
  - RESERVED（他者が回答中/予約中）

#### `/survey`（設問入力）
- `rt` がなければ表示不可
- 送信 → POST `/api/submit`
- 成功 → `/done`
- 失敗（期限切れ/使用済み等）→ リトライ導線（最初に戻る）

#### `/done`
- 完了表示のみ

### 5.2 管理者導線

#### `/admin`（一覧）
- groups一覧、進捗（回答数/N）
- PDF生成状況

#### `/admin/new`
- org、担当者、メール、N、assessment_version選択
- 作成でID+鍵を発行し、コピペ用に一覧表示＋CSVダウンロード

#### `/admin/groups/:id`
- ID+鍵一覧（コピー）
- 回答状況
- PDFリンク（生成済みなら）
- 手動操作：
  - 再生成（PoC）
  - 強制レポート生成
  - 再送（将来）

## 6. API仕様（Next.js Route Handlers）

### 6.1 POST `/api/admin/groups`（案件作成 + ID発行）
**req:**
```
{
  "org_name": "Example Inc.",
  "owner_name": "Taro Yamada",
  "owner_email": "taro@example.com",
  "requested_count": 20,
  "assessment_version": "v1"
}
```

**res:**
```
{
  "group_id": "uuid",
  "invitations": [
    { "id": "uuid", "participant_id": "A001", "participant_key": "K123" }
  ]
}
```

ID衝突は全体では許容だが、**同一group内の重複は生成時に避ける**。

### 6.2 POST `/api/reserve`（送信前チェック＝予約）
**req:**
```
{ "participant_id": "A001", "participant_key": "K123" }
```

**res（ok）:**
```
{ "reservation_token": "uuid", "expires_at": "2024-01-01T00:00:00Z", "group_id": "uuid" }
```

**res（ng）:**
```
{ "reason": "INVALID" | "USED" | "RESERVED" }
```

**挙動**
- invitationsを検索（groupはID+鍵から引ける）
- USEDなら拒否
- RESERVED && reserved_until > now なら拒否
- それ以外なら
  - state=RESERVED
  - reserved_token=uuid
  - reserved_until=now+TTL
を保存

### 6.3 POST `/api/submit`（回答保存）
**req:**
```
{ "reservation_token": "uuid", "answers": { "q1": 4, "q2": 2 } }
```

**res（ok）:**
```
{ "response_id": "uuid" }
```

**res（ng）:**
```
{ "reason": "TOKEN_EXPIRED" | "USED" | "DUPLICATE" | "INVALID" }
```

**重要：二重ロック**
- 予約トークン検証（期限内）
- DBトランザクションで
  - invitation状態確認
  - responses insert（UNIQUE(invitation_id)で物理拒否）
  - invitationをUSEDに更新

### 6.4 POST `/api/jobs/analyze`（PoCは内部呼び出し）
- group_idを受けて
- Dify個別/群分析
- report生成

## 7. ジョブ設計（Vercel Cron）

### 7.1 PoCのジョブ（最小）
1. `cleanup-reservations`（5分おき）
   - RESERVEDで期限切れの invitation を UNUSED に戻す

2. `check-and-generate-report`（5分おき）
   - groupsで COLLECTING のものを走査
   - 回答数 == requested_count なら ANALYZINGへ遷移して解析開始

3. `send-email`（PoCではOFF）
   - DONEで未送付のものを送る

### 7.2 長い処理の扱い（現実策）
- Difyのworkflow実行は blocking がCloudflare 100秒制限と明記されているため、長い分析は非同期化が必要な可能性。
- Vercel Functionsも最大実行時間が設定/プランに依存するため、重いPDF生成や長い解析は「ジョブ分割」「外部ワーカー（Cloud Run等）」に逃がす設計をあらかじめ持つ。

PoCは「blockingで100秒以内」「PDFは軽量」でまず通す。伸びたら worker 分離。

## 8. レポート生成（PDF）仕様

### 8.1 PoC推奨：HTML + SVGレーダー → PDF
- レーダーチャートは 外部サービスを使わず、サーバー側でSVGを生成（通信ブロック懸念を減らす）
- PDF化は
  - 低負荷なら `pdf-lib` / `@react-pdf/renderer`
  - 高い見た目が必要なら Headless Chromium（ただし実行時間に注意）

### 8.2 レポートの構成
- 表紙：組織名、日付、案件ID
- サマリ：群の結論（LLM）
- 定量：
  - Dimension平均（レーダー）
  - 分布（棒/箱ひげ：PoCでは棒でOK）
- 定性：
  - 上位テーマ
  - 推奨アクション（短期/中期）
  - 個別（10名分）：要約＋推奨（PoCは1段落ずつ）

## 9. メール送信（Resend）仕様（段階④）

### 9.1 送信方式
- PoC：メール本文に レポートリンク（署名付きURL）
- 本番：リンク＋（必要なら）PDF添付

### 9.2 DNS/配信要件
- SPF / DKIM は必須
- DMARCは推奨（なりすまし/到達率向上）

## 10. GitHub連携・運用（CI/CD）

### 10.1 ブランチ戦略（PoC）
- main：本番（Production）
- dev：検証（Preview/Stage）
- feature/*：PR→Preview Deployment

### 10.2 環境変数
- VercelのProject Settingsで Preview / Production の変数を分ける
- Supabaseも Stage/Prodでプロジェクトを分ける（DB分離）

### 10.3 GitHub Actions（最低限）
- lint（ESLint）
- typecheck（tsc）
- test（最低限：APIのユニット）
- migration check（SQLの差分検証：任意）

## 11. PoC計画（4段階）

Milestone 1（①）：申込→ID+鍵発行→回答→集計
- Done条件
  - `/admin/new` で group 作成→ID+鍵 N件発行できる
  - `/` でID+鍵を入力→予約できる
  - `/survey` で回答送信→二重回答は拒否される
  - 管理画面で回答数/進捗が見える

Milestone 2（②）：Dify連携→定性/定量→Docs相当のレポート生成
- Done条件
  - Dify workflowを叩いてJSONを保存できる
  - そのJSONからPDFを生成してStorageに保存できる（リンク表示）

Milestone 3（③）：図示（レーダー）
- Done条件
  - 定量スコアからレーダー図がPDFに入る

Milestone 4（④）：メール自動送付（Resend）
- Done条件
  - DONEになったら owner_email に送信できる
  - SPF/DKIM/DMARCの設定手順をドキュメント化
  - 送信ログが残る

## 12. 確認ポイント（要回答）
1. PDFの生成方式：PoCは「軽く確実」優先で
   - A: pdf-lib / React-PDF（依存少）
   - B: HTML→PDF（見た目強、ただし重くなりがち）
2. Difyは“blockingで100秒以内”に収める設計で良いか？
   - 長くなる可能性があるなら、Milestone2で早めに非同期ジョブ設計を入れる
