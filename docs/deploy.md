# デプロイ手順

## ローカル開発（Docker Compose）

```bash
# ビルド & 起動
docker compose up --build

# バックグラウンド起動
docker compose up --build -d

# 停止
docker compose down
```

サーバーは http://localhost:8080 でアクセス可能。
`data/` ディレクトリがボリュームマウントされるため、データはホスト側に永続化される。

## Google Cloud Run へのデプロイ

### 前提条件

- Google Cloud プロジェクトが作成済み
- `gcloud` CLI がインストール・認証済み
- Artifact Registry が有効化済み

### 1. 初回セットアップ

```bash
# プロジェクト ID を設定
export PROJECT_ID=your-project-id
export REGION=asia-northeast1

# Artifact Registry リポジトリ作成
gcloud artifacts repositories create study-group \
  --repository-format=docker \
  --location=$REGION

# Docker 認証設定
gcloud auth configure-docker ${REGION}-docker.pkg.dev
```

### 2. イメージのビルド & プッシュ

```bash
# Cloud Build でビルド（ローカルで Docker 不要）
gcloud builds submit --tag ${REGION}-docker.pkg.dev/${PROJECT_ID}/study-group/server

# または、ローカルでビルドしてプッシュ
docker build -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/study-group/server .
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/study-group/server
```

### 3. Cloud Run デプロイ

```bash
gcloud run deploy study-group-server \
  --image ${REGION}-docker.pkg.dev/${PROJECT_ID}/study-group/server \
  --platform managed \
  --region $REGION \
  --port 8080 \
  --allow-unauthenticated \
  --memory 256Mi \
  --min-instances 0 \
  --max-instances 1
```

### データ永続化について

Cloud Run はステートレスなため、コンテナ再起動でデータがリセットされる。

**現在の方針**: defaultData にフォールバックされるため、データが消えてもアプリは動作する。
低トラフィック・少人数の勉強会アプリなので、当面はこの制約を許容する。

**将来の選択肢**:
- **Cloud Storage (GCS)**: JSON ファイルを GCS に読み書きする。Storage モジュールを差し替えるだけで対応可能。
- **Compute Engine**: 常時起動 VM ならローカルファイルが使える。e2-micro は無料枠あり。
- **Firestore**: Google のドキュメント DB。無料枠が大きい。

### コスト見積もり

Cloud Run は低トラフィックなら無料枠内で運用可能:
- 月 200 万リクエストまで無料
- 月 36 万 vCPU 秒まで無料
- 月 1GB メモリまで無料

勉強会アプリの規模なら完全に無料枠内に収まる見込み。
