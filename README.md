# Study Group App

週一エンジニア勉強会の管理アプリ。Haskell 学習プロジェクトを兼ねており、JSON パーサー・HTTP リクエスト/レスポンスのパース・ルーティング・CLI 引数パース・URL エンコード/デコード・UTF-8 エンコード/デコードを自前で実装している。

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
- **自前実装が原則**: 当初は `base` のみで全て書く方針だったが、TCP ソケットと HTTPS の TLS ハンドシェイクは現実的に自前が困難なので、最小限のライブラリに委譲している
- **データ永続化**: JSON ファイル 1 枚 (`data/study-group.json`)。RDB は使わない
- **コーディング規約**: 純粋関数と IO の明確な分離、代数的データ型 + パターンマッチ、`map` / `filter` / `foldr` 等での宣言的記述

### 自前実装している部分

- JSON パーサー / プリンタ / エンコーダ (`StudyGroup.Json.*`)
- HTTP リクエスト / レスポンスのパース・組み立て (`StudyGroup.Http.Parser`, `StudyGroup.Http.Response`)
- URL ルーティング (`StudyGroup.Http.Router`)
- HTTP サーバーのアクセプトループ (`StudyGroup.Http.Server`、`network` の Socket API の上に直接書いている)
- HTTP クライアント (HTTP 専用、学習成果として `StudyGroup.Http.Client` に残してある)
- CLI 引数パース (`StudyGroup.Cli.parseArgs`、パターンマッチで宣言的に書く)
- URL パーセントエンコード / デコード (日本語対応)
- UTF-8 エンコード / デコード (RFC 3629 準拠)

### 委譲している外部ライブラリ

| ライブラリ | 用途 | なぜ委譲したか |
|---|---|---|
| `network` | TCP ソケット (`Network.Socket`) | OS のソケット API を `base` から直接叩く手段がない |
| `bytestring` | バイト列の取り扱い | TLS クライアントとのインターフェイス・バイナリ I/O のため |
| `http-client` + `http-client-tls` | CLI から HTTPS API サーバーへリクエストを送る (`StudyGroup.Http.ClientTls`) | TLS ハンドシェイクと証明書検証を自前で書くのは学習スコープ外。Cloud Run の HTTPS エンドポイントに繋ぐためにここだけ妥協 |

詳細は [`CLAUDE.md`](./CLAUDE.md) と [`docs/overview.md`](./docs/overview.md) を参照。

## セットアップと起動 (Docker Compose 推奨)

ローカル実行は Docker Compose を使うのが最短ルート。GHC / Cabal をホストにインストールする必要がない。

### 前提

- Docker / Docker Compose がインストール済み

### API サーバーを起動

```bash
# ビルド & 起動 (フォアグラウンド)
docker compose up --build

# バックグラウンド起動
docker compose up --build -d

# 停止
docker compose down
```

- ポート: `http://localhost:8080`
- データ: ホストの `./data` がコンテナの `/app/data` にマウントされ、`study-group.json` がホスト側に永続化される
- ファイルが無い / 壊れている場合は `defaultData` で起動する

### CLI をコンテナ内で実行

CLI バイナリ (`study-group`) も同じイメージに含まれているため、サーバー起動中の同じコンテナから叩ける:

```bash
# ヘルプ
docker compose exec server study-group
docker compose exec server study-group --help

# メンバー一覧
docker compose exec server study-group interests list

# 特定メンバーの興味一覧
docker compose exec server study-group interests list nori

# 興味を追加 / 削除
docker compose exec server study-group interests add nori Rust
docker compose exec server study-group interests remove nori Rust

# 勉強会予定の一覧 / 追加
docker compose exec server study-group sessions list
docker compose exec server study-group sessions add 2026-04-16 "HTTP server"
```

CLI はデフォルトで `http://localhost:8080` に接続する。コンテナ内で動かす場合、サーバーが同じコンテナで listen しているのでそのままで届く。

### 接続先 API サーバーを切り替える

CLI は環境変数 `STUDY_GROUP_API_URL` を読み、未設定なら `http://localhost:8080` に接続する。Cloud Run など別ホストの API サーバーを叩きたい場合:

```bash
docker compose exec -e STUDY_GROUP_API_URL=https://study-group-server-xxxxx.asia-northeast1.run.app \
  server study-group interests list
```

HTTPS の場合は内部の `http-client-tls` が TLS ハンドシェイクを行うので、追加の設定は不要。

## Docker を使わずに直接ビルドする (開発者向け)

Haskell を学習しながら触りたい場合は `cabal` で直接ビルドできる。

### 前提

- GHC 9.6 系 + Cabal 3.x (推奨: [GHCup](https://www.haskell.org/ghcup/) 経由でインストール)

### ビルドと起動

```bash
# 全ターゲットをビルド (初回は依存解決に時間がかかる)
cabal build all

# API サーバーを起動
cabal run study-group-server

# CLI を別ターミナルから実行
cabal run study-group -- --help
cabal run study-group -- interests list
cabal run study-group -- sessions add 2026-04-16 "HTTP server"
```

`cabal run` の `--` 以降が CLI 本体への引数になる点に注意。

## Cloud Run へのデプロイ

Cloud Run への本番デプロイ手順 (GCS Volume Mount による永続化を含む) は [`docs/deploy.md`](./docs/deploy.md) を参照。

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
