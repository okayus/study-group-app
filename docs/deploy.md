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
export BUCKET=study-group-app-data

# Artifact Registry リポジトリ作成
gcloud artifacts repositories create study-group \
  --repository-format=docker \
  --location=$REGION

# Docker 認証設定
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# データ永続化用の GCS バケットを作成
# - Cloud Run と同一 region にすることで egress 無料
# - Standard クラスは min storage duration が無く頻繁な書き込みに適する
gcloud storage buckets create gs://${BUCKET} \
  --location=${REGION} \
  --default-storage-class=STANDARD \
  --uniform-bucket-level-access
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
  --memory 512Mi \
  --min-instances 0 \
  --max-instances 1 \
  --execution-environment gen2 \
  --add-volume name=data,type=cloud-storage,bucket=${BUCKET} \
  --add-volume-mount volume=data,mount-path=/app/data
```

ポイント:

- `--execution-environment gen2`: Cloud Storage Volume Mount は第二世代実行環境でのみ利用可能
- `--add-volume` / `--add-volume-mount`: GCS バケットを `/app/data` にマウントする。アプリはこのパスへ通常のファイル I/O を行うだけで GCS に永続化される（GCS Fuse 経由）
- `--memory 512Mi`: GCS Fuse のキャッシュとマウント管理ぶん、256Mi から増量する

### データ永続化について

`/app/data/study-group.json` を GCS バケットに Volume Mount することで永続化している。

**採用方針**: Cloud Run の Cloud Storage Volume Mount

- アプリ側のコード変更が不要（既存の `Storage.saveData` / `loadData` がそのまま動く）
- `base` のみという依存方針を維持できる（GCS クライアントライブラリ不要）
- Cloud Run のサービス設定だけで完結する
- 同一 region なら egress 無料、このアプリ規模なら GCS の無料枠内

**動作の流れ**:

1. Cloud Run コンテナ起動時に GCS Fuse が `gs://study-group-app-data` を `/app/data` にマウント
2. `Storage.saveData` の `withFile WriteMode` / `hPutStr` がそのまま GCS のオブジェクトに反映される
3. コンテナが落ちても次回起動時に同じ JSON を `loadData` で読み戻せる

**他案との比較**:

| 案 | 採否理由 |
|---|---|
| **GCS Volume Mount** ← 採用 | コード変更ゼロ、`base` 縛りに整合、料金もほぼ無料 |
| GCS API を Storage モジュールから直接叩く | `google-cloud-storage` 等のライブラリ依存が増える。base 縛りに反する |
| Firestore | 同上、依存が大きい |
| Compute Engine + ローカルファイル | 常時起動コスト、運用複雑化 |

**ローカル開発との互換性**: ローカル (`cabal run study-group-server` / `docker compose up`) では従来通りローカルファイルに書き込まれる。マウント設定は Cloud Run 側にしか存在しないため、アプリのコードを分岐させる必要はない。

### コスト見積もり

Cloud Run は低トラフィックなら無料枠内で運用可能:
- 月 200 万リクエストまで無料
- 月 36 万 vCPU 秒まで無料
- 月 1GB メモリまで無料

勉強会アプリの規模なら完全に無料枠内に収まる見込み。

GCS 側も同様にほぼ無料枠内:

- ストレージ: $0.020/GB/月（1KB 未満なので事実上 $0）
- Class A 操作（write）: $0.05/10,000 ops、月 50,000 ops 無料
- Class B 操作（read）: $0.004/10,000 ops、月 50,000 ops 無料
- 同一 region egress: $0

参考: [Cloud Storage volume mounts](https://cloud.google.com/run/docs/configuring/services/cloud-storage-volume-mounts), [Cloud Storage pricing](https://cloud.google.com/storage/pricing)
