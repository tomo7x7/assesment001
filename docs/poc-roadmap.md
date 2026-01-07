# PoC（4段階ロードマップ）素案

## Milestone 1（①）：申込→ID+鍵発行→回答→集計

**Done条件**
- `/admin/new` で group 作成→ID+鍵 N件発行できる
- `/` でID+鍵を入力→予約できる
- `/survey` で回答送信→二重回答は拒否される
- 管理画面で回答数/進捗が見える

**Issue例**
- DB migration（groups/invitations/responses）
- Admin UI（create/list/detail）
- Reserve API（予約）
- Submit API（保存）
- Basic rate limit（軽く）

## Milestone 2（②）：Dify連携→定性/定量→Docs相当のレポート生成

**Done条件**
- Dify workflowを叩いてJSONを保存できる
- そのJSONからPDFを生成してStorageに保存できる（リンク表示）

**Issue例**
- Dify client（execute workflow）
- 個別分析（submit後）
- 群分析（N件揃ったら）
- PDF生成（簡易版）

## Milestone 3（③）：図示（レーダー）

**Done条件**
- 定量スコアからレーダー図がPDFに入る

**Issue例**
- dimension平均計算
- SVGレーダー生成
- PDF埋め込み

## Milestone 4（④）：メール自動送付（Resend）

**Done条件**
- DONEになったら owner_email に送信できる
- SPF/DKIM/DMARCの設定手順をドキュメント化
- 送信ログが残る

**Issue例**
- Resend送信モジュール
- DNS設定ガイド
- 送信ジョブ（cron）
