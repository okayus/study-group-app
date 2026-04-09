# ============================================================
# Stage 1: ビルド
# ============================================================
FROM haskell:9.6 AS builder

WORKDIR /build

# 依存解決を先にキャッシュするため、cabal ファイルだけ先にコピー
COPY study-group-app.cabal ./
RUN cabal update && cabal build --only-dependencies all

# ソースコードをコピーしてビルド
COPY src/ src/
COPY app/ app/

RUN cabal build all \
 && cp $(cabal list-bin study-group-server) /build/study-group-server \
 && cp $(cabal list-bin study-group) /build/study-group

# ============================================================
# Stage 2: ランタイム（軽量イメージ）
# ============================================================
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends libgmp10 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/study-group-server /usr/local/bin/study-group-server
COPY --from=builder /build/study-group /usr/local/bin/study-group

# データディレクトリを作成（ボリュームマウント用）
# data/ は .gitignore 対象のため COPY せず、起動時に defaultData にフォールバックする
RUN mkdir -p /app/data

EXPOSE 8080

CMD ["study-group-server"]
