# リポジトリ構成・環境変数・API・DB・ジョブ・セキュリティ要点

## 1. リポジトリ構成（想定）
```
.
├── docs/                         # 仕様書・運用ドキュメント
├── src/
│   ├── app/                      # Next.js App Router (UI + API)
│   │   ├── api/                  # Route Handlers
│   │   ├── admin/                # 管理画面
│   │   ├── survey/               # 回答画面
│   │   └── done/                 # 完了画面
│   ├── lib/
│   │   ├── db.ts                 # DB接続/Supabase client
│   │   ├── dify.ts               # Dify client
│   │   ├── resend.ts             # Resend client
│   │   └── pdf/                  # PDF生成
│   └── jobs/                     # cron handlers
├── supabase/
│   └── migrations/               # SQL migrations
└── .env.example                  # 環境変数テンプレ
```

## 2. 環境変数（例）

> **注意**: `SUPABASE_SERVICE_ROLE_KEY` はサーバー専用。

```
# Supabase
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

# Dify
DIFY_BASE_URL=
DIFY_API_KEY=
DIFY_WORKFLOW_ID=

# Resend
RESEND_API_KEY=
RESEND_FROM_EMAIL=

# App
APP_BASE_URL=
RESERVATION_TTL_MINUTES=30

# Vercel Cron (shared secret)
CRON_SECRET=
```

## 3. API（Route Handlers）

### 3.1 `/api/admin/groups`（POST）
- 入力: org_name, owner_name, owner_email, requested_count, assessment_version
- 出力: group_id + invitations[]
- ロジック: group作成→ID+鍵N件発行

### 3.2 `/api/reserve`（POST）
- 入力: participant_id, participant_key
- 出力: reservation_token, expires_at, group_id
- 例外: INVALID / USED / RESERVED

### 3.3 `/api/submit`（POST）
- 入力: reservation_token, answers
- 出力: response_id
- 例外: TOKEN_EXPIRED / USED / DUPLICATE / INVALID

### 3.4 `/api/jobs/analyze`（POST）
- 入力: group_id
- 出力: report paths
- 用途: Dify分析・PDF生成

## 4. DB（Supabase / Postgres）

- `groups`: 案件/グループ
- `invitations`: ID+鍵台帳
- `responses`: 回答
- `assessments`, `dimensions`, `questions`: 設問体系（版管理）

詳細は `supabase/migrations/001_init.sql` を参照。

## 5. ジョブ設計（Vercel Cron）

1. `cleanup-reservations`（5分おき）
   - RESERVEDかつ期限切れをUNUSEDに戻す

2. `check-and-generate-report`（5分おき）
   - COLLECTINGのgroupで回答数 == requested_count なら ANALYZING へ遷移

3. `send-email`（PoCではOFF）
   - DONEで未送付のgroupへメール

## 6. セキュリティ要点

- `service_role` key は絶対にフロントへ渡さない
- 予約トークンは短寿命（例: 30分）
- `/api/reserve` `/api/submit` はレート制限（Upstash等）を推奨
- RLSはPoCでは任意だが、本番移行時に必須
