# 開発計画

**方針**: 外部ライブラリを使わず、GHC 標準ライブラリ（base）のみで実装する。

---

## Phase 1: データモデルとファイル永続化

### Step 1: プロジェクトセットアップ
- [x] Cabal プロジェクト初期化（依存は `base` のみ）
- [x] ディレクトリ構成を決める

### Step 2: データモデル定義（代数的データ型）
- [x] `Member` - メンバー名
- [x] `Interest` - 興味テーマ（メンバーに紐づく）
- [x] `StudySession` - 勉強会予定（日程・テーマ）
- [x] JSON 的なフォーマットでのシリアライズ/デシリアライズを自前実装

### Step 3: ファイル永続化
- [x] データの読み書き（`System.IO`）
- [x] データファイルのフォーマット設計（自前 JSON or シンプルなテキスト形式）

## Phase 2: HTTP サーバー（自前実装）

### Step 4: TCP ソケットで HTTP サーバーを作る
- [x] `Network.Socket` でリクエストを受け付け
- [x] HTTP リクエストのパース（メソッド、パス、ボディ）
- [x] HTTP レスポンスの組み立て
- [x] ルーティング（パターンマッチで振り分け）

### Step 5: API エンドポイント実装
- [x] `GET  /members` - メンバー一覧
- [x] `GET  /members/:name/interests` - メンバーの興味リスト
- [x] `POST /members/:name/interests` - 興味の追加
- [x] `DELETE /members/:name/interests/:topic` - 興味の削除
- [x] `GET  /sessions` - 勉強会予定一覧
- [x] `POST /sessions` - 勉強会予定の追加

## Phase 3: CLI クライアント（自前実装）

### Step 6: CLI 実装
- [x] コマンドライン引数パース（`System.Environment.getArgs` + パターンマッチ）
- [x] HTTP クライアント（`Network.Socket` で API サーバーに接続）
- [x] コマンド一覧:
  - `study-group interests list [NAME]` - 興味リスト表示
  - `study-group interests add NAME TOPIC` - 興味の追加
  - `study-group interests remove NAME TOPIC` - 興味の削除
  - `study-group sessions list` - 予定一覧表示
  - `study-group sessions add DATE TOPIC` - 予定の追加

## Phase 4: Docker & デプロイ

### Step 7: コンテナ化
- [ ] マルチステージ Dockerfile
- [ ] docker-compose.yml（ローカル開発用）

### Step 8: Google Cloud ホスティング調査・デプロイ
- [ ] ホスティング候補の比較調査（下記参照）
- [ ] デプロイ設定・実施

---

## Google Cloud ホスティング候補（要調査）

| サービス | 特徴 | 月額目安 |
|:---------|:-----|:---------|
| **Cloud Run** | コンテナベース、リクエスト課金、無料枠あり | 低トラフィックなら無料〜数百円 |
| **Compute Engine (e2-micro)** | 常時起動 VM、無料枠あり | 無料枠内 or 月数百円 |

### 調査ポイント
- Cloud Run が最有力（Docker イメージをそのままデプロイ、低トラフィックなら無料枠内）
- ただし Cloud Run はステートレス → JSON ファイルの永続化をどうするか
  - 案1: Cloud Storage（GCS）に読み書き
  - 案2: Compute Engine にして普通にファイル保存
  - 案3: 将来的に DB に移行

---

## 学習ポイント（Haskell ロードマップとの対応）

この開発で全フェーズを実践的にカバーできる:

| ロードマップ Phase | この開発で触れる部分 |
|:-------------------|:---------------------|
| Phase 1: 不変性と純粋関数 | データモデルの不変設計、純粋な変換関数 |
| Phase 2: 代数的データ型 | Member / Interest / Session の型定義、パターンマッチ |
| Phase 3: 高階関数と合成 | JSON パース、データ変換パイプライン |
| Phase 4: モナドとI/O | ファイル I/O・ソケット操作の副作用分離 |
| Phase 5: エコシステム | **自前で HTTP サーバー・JSON パーサーを作ることで、ライブラリの裏側を理解** |
