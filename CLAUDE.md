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

## 実装ワークフロー

実装タスクを受けたら、以下の手順で自律的に進めること:

1. **ブランチ作成**: `git checkout -b <feature-name>` でフィーチャーブランチを作成
2. **空コミット + Push**: `git commit --allow-empty -m "<message>"` → `git push -u origin <branch>`
3. **PR 作成**: `gh pr create` でドラフト PR を作成。PR ボディには実装計画を記載する
4. **実装**: 計画に沿って実装を進め、コミットを積む
5. **PR コメント**: 各ファイルの役割と各関数について「なぜ必要か・なぜそのシグネチャか・なぜその実装か」を PR コメントとして投稿する
6. **完了**: 実装が終わったらユーザーに報告する

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
