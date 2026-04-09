# Study Group App

週一エンジニア勉強会の管理アプリ。Haskell 学習プロジェクトを兼ねており、HTTP サーバー・JSON パーサー・CLI 引数パーサーなどを **`base` パッケージのみ** で自前実装している。

## 構成

```
┌─────────────┐    HTTP/JSON    ┌────────────────┐    file I/O    ┌────────────────────┐
│  CLI client │ ◄─────────────► │  HTTP server   │ ◄────────────► │ data/study-group.  │
│ study-group │                 │ study-group-   │                │ json               │
│             │                 │ server         │                │ (or GCS Volume     │
│             │                 │                │                │  Mount on Cloud Run)│
└─────────────┘                 └────────────────┘                └────────────────────┘
```

- **API サーバー** (`study-group-server`): HTTP リクエストを受け、JSON ファイルを読み書きする
- **CLI クライアント** (`study-group`): API サーバーに HTTP リクエストを送ってメンバー / 興味 / 勉強会予定を操作する

## 技術方針

- **言語**: Haskell (GHC 9.6 系で確認)
- **依存ライブラリは `base` のみ**: HTTP サーバー、JSON パース・エンコード、CLI 引数パース、URL エンコード/デコード、HTTPS クライアント (TLS ハンドシェイクは `openssl` バイナリ経由) を全て自前実装している
- **データ永続化**: JSON ファイル 1 枚 (`data/study-group.json`)。RDB は使わない
- **コーディング規約**: 純粋関数と IO の明確な分離、代数的データ型 + パターンマッチ、`map` / `filter` / `foldr` 等での宣言的記述

詳細は [`CLAUDE.md`](./CLAUDE.md) と [`docs/overview.md`](./docs/overview.md) を参照。

## セットアップ

### 前提

- GHC 9.6 系 + Cabal 3.x (推奨: [GHCup](https://www.haskell.org/ghcup/) 経由でインストール)
- `openssl` コマンド (HTTPS で API サーバーに接続する場合のみ)

### 依存解決とビルド

```bash
# 全ターゲットをビルド (初回は依存解決に時間がかかる)
cabal build all
```

ビルドが通れば `study-group-server` (API サーバー) と `study-group` (CLI) の 2 つのバイナリが生成される。

## ローカルでの使い方

### 1. API サーバーを起動

```bash
cabal run study-group-server
```

- ポート: `8080`
- データファイル: カレントディレクトリ直下の `data/study-group.json` を読み書きする
- ファイルが存在しない / 壊れている場合は `defaultData` で起動する

### 2. CLI を別ターミナルから実行

```bash
# ヘルプを表示
cabal run study-group
cabal run study-group -- --help

# メンバー一覧
cabal run study-group -- interests list

# 特定メンバーの興味一覧
cabal run study-group -- interests list nori

# 興味を追加
cabal run study-group -- interests add nori Rust

# 興味を削除
cabal run study-group -- interests remove nori Rust

# 勉強会予定一覧
cabal run study-group -- sessions list

# 勉強会予定を追加
cabal run study-group -- sessions add 2026-04-16 "HTTP server"
```

`cabal run` の `--` 以降が CLI 本体への引数になる点に注意。

### 3. 接続先 API サーバーを切り替える

CLI は環境変数 `STUDY_GROUP_API_URL` を読み、未設定なら `http://localhost:8080` に接続する。Cloud Run など別ホストの API サーバーを叩きたい場合:

```bash
export STUDY_GROUP_API_URL=https://study-group-server-xxxxx.asia-northeast1.run.app
cabal run study-group -- interests list
```

HTTPS の場合は内部で `openssl s_client` を起動して TLS ハンドシェイクを行う。

## Docker / Cloud Run でのデプロイ

`docker compose up --build` でローカルにコンテナ起動できる。Cloud Run へのデプロイ手順 (GCS Volume Mount による永続化を含む) は [`docs/deploy.md`](./docs/deploy.md) を参照。

## ディレクトリ構成

```
.
├── app/
│   ├── Server.hs          # API サーバーのエントリポイント
│   └── Client.hs          # CLI のエントリポイント
├── src/StudyGroup/
│   ├── Api.hs             # ルーティング + リクエストハンドラ
│   ├── Cli.hs             # CLI コマンド定義 + HTTP 呼び出し
│   ├── Operations.hs      # ドメインロジック (純粋関数)
│   ├── Storage.hs         # JSON ファイルの読み書き
│   ├── Types.hs           # ドメイン型定義
│   ├── Http/              # HTTP サーバー / クライアント / ルーター
│   └── Json/              # JSON パーサー / プリンタ / エンコーダ
├── data/
│   └── study-group.json   # 永続化された全データ
├── docs/
│   ├── overview.md        # プロジェクト概要
│   ├── plan.md            # 開発計画
│   ├── plan-detail.md     # 詳細設計
│   ├── deploy.md          # デプロイ手順 (Docker / Cloud Run)
│   └── roadmap.md         # 実装ロードマップ
├── Dockerfile
├── docker-compose.yml
├── study-group-app.cabal
├── CLAUDE.md              # Claude Code 向けの指示書
└── README.md              # このファイル
```

## 関連ドキュメント

- [プロジェクト概要](./docs/overview.md)
- [開発計画](./docs/plan.md)
- [詳細設計](./docs/plan-detail.md)
- [デプロイ手順](./docs/deploy.md)
- [実装ロードマップ](./docs/roadmap.md)
