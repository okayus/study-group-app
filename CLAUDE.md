# Study Group App

週一エンジニア勉強会の管理アプリ。Haskell 学習プロジェクトを兼ねる。

## プロジェクト概要

- 詳細: `docs/overview.md`
- 開発計画: `docs/plan.md`
- Haskell 学習ロードマップ: `../fanctional-programming-in-haskell/roadmap.md`

## 技術方針

- **言語**: Haskell
- **外部ライブラリ不使用**: 依存は `base` のみ。HTTP サーバー・JSON パース・CLI 引数パースを全て自前実装する
- **データ永続化**: JSON ファイル（RDB は使わない）
- **構成**: API サーバー + CLI クライアントの2つの実行バイナリ

## コーディング規約

- 純粋関数と IO を明確に分離する（ロードマップ Phase 4 の実践）
- 代数的データ型とパターンマッチを積極的に使う
- ループ（再帰以外の反復処理）は使わず、`map`, `filter`, `foldr` 等で書く
- 不正な状態を型で表現不可能にする設計を心がける

## ビルド・実行

```bash
# ビルド（Cabal）
cabal build all

# API サーバー起動
cabal run study-group-server

# CLI
cabal run study-group -- interests list
cabal run study-group -- sessions list
```
