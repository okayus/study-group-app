# 詳細実装計画

## 技術的な補足: `network` パッケージについて

`Network.Socket` は `base` パッケージに含まれていない。TCP ソケットを使うには `network` パッケージが必要。

**方針**: `network` を唯一の外部依存として許可する。FFI で C の `socket()` を直接呼ぶ方法もあるが、学習コストが高くプロジェクトの目的（型設計・純粋関数・IO分離の実践）から逸れる。

---

## ディレクトリ構成

```
study-group-app/
├── CLAUDE.md
├── study-group-app.cabal
├── docs/
│   ├── overview.md
│   ├── plan.md
│   └── plan-detail.md
├── data/
│   └── study-group.json          -- 永続化データ（実行時に自動生成）
├── src/
│   ├── StudyGroup/
│   │   ├── Types.hs              -- データモデル（代数的データ型）
│   │   ├── Json/
│   │   │   ├── Types.hs          -- JSON の AST 型定義
│   │   │   ├── Parser.hs         -- JSON パーサー（パーサーコンビネータ自前実装）
│   │   │   ├── Printer.hs        -- JSON → String レンダラー
│   │   │   └── Encode.hs         -- ドメイン型 ⇔ JSON 変換
│   │   ├── Storage.hs            -- ファイル永続化（IO層）
│   │   ├── Operations.hs         -- ドメインロジック（純粋関数）
│   │   ├── Http/
│   │   │   ├── Types.hs          -- Request / Response 型
│   │   │   ├── Parser.hs         -- HTTP リクエストパーサー
│   │   │   ├── Response.hs       -- HTTP レスポンスビルダー
│   │   │   └── Router.hs         -- ルーティング（パターンマッチ）
│   │   └── Api/
│   │       └── Handlers.hs       -- API エンドポイントハンドラ
├── app/
│   ├── Server.hs                 -- サーバー Main（エントリポイント）
│   └── Client.hs                 -- CLI Main（エントリポイント）
├── Dockerfile
└── docker-compose.yml
```

---

## Phase 1: データモデルとファイル永続化

### Step 1.1: Cabal プロジェクト初期化

**ファイル**: `study-group-app.cabal`

- `cabal-version: 3.0`
- `common` ブロックで共通設定（`base`, `network`）をまとめる
- ライブラリ（`src/`）+ 2つの実行バイナリ（`app/Server.hs`, `app/Client.hs`）構成
- `default-language: Haskell2010`, `ghc-options: -Wall`

**検証**: 全モジュールを空（`module X where` のみ）で作成し、`cabal build all` が通ること。

---

### Step 1.2: ドメイン型定義

**ファイル**: `src/StudyGroup/Types.hs`

```haskell
data MemberName = Shiraoka | Nori
  deriving (Show, Eq)

data Interest = Interest
  { interestMember :: MemberName
  , interestTopic  :: String
  } deriving (Show, Eq)

data StudySession = StudySession
  { sessionDate  :: String   -- "YYYY-MM-DD" 形式
  , sessionTopic :: String
  } deriving (Show, Eq)

data AppData = AppData
  { appInterests :: [Interest]
  , appSessions  :: [StudySession]
  } deriving (Show, Eq)
```

**設計判断**:

- `MemberName` を列挙型（Sum Type）にして不正なメンバー名を型で防ぐ（「不正な状態を型で表現不可能にする」の実践）
- `String` ベースで開始（`Text` は後から移行可能）
- `AppData` がアプリ全体の状態を表し、JSON ファイルに永続化する

**検証**: GHCi で型をロードし、値を生成・表示できること。

---

### Step 1.3: JSON AST 型と自前パーサーコンビネータ

このプロジェクトで最も学習価値の高い部分。パーサーコンビネータを一から構築する。

#### Step 1.3a: JSON AST 型

**ファイル**: `src/StudyGroup/Json/Types.hs`

```haskell
data JsonValue
  = JsonNull
  | JsonBool Bool
  | JsonNumber Double
  | JsonString String
  | JsonArray [JsonValue]
  | JsonObject [(String, JsonValue)]
  deriving (Show, Eq)
```

`JsonObject` は連想リスト `[(String, JsonValue)]` で表現（`Map` よりシンプルで学習向き）。

#### Step 1.3b: パーサーコンビネータ基盤

**ファイル**: `src/StudyGroup/Json/Parser.hs`

**アプローチ**: `newtype Parser a = Parser (String -> Maybe (a, String))` を定義し、型クラスインスタンスを手動実装する。

**実装順序**:

1. `Parser` newtype 定義と `runParser` 関数
2. `Functor` インスタンス（`fmap`）
3. `Applicative` インスタンス（`pure`, `<*>`）
4. `Alternative` インスタンス（`empty`, `<|>`）
5. 基本パーサー群:
   - `charP :: Char -> Parser Char` -- 1文字マッチ
   - `stringP :: String -> Parser String` -- 文字列マッチ
   - `spanP :: (Char -> Bool) -> Parser String` -- 条件マッチ
   - `ws :: Parser String` -- 空白読み飛ばし
   - `sepBy :: Parser a -> Parser b -> Parser [a]` -- セパレータ区切り
6. JSON 値パーサー群:
   - `jsonNull`, `jsonBool`, `jsonNumber`, `jsonString`
   - `jsonArray`, `jsonObject`
   - `jsonValue` -- 全体を `<|>` で合成

**TS との対比**: TypeScript で `type Parser<A> = (input: string) => [A, string] | null` を作り `.map()` や `.flatMap()` を定義するのと概念的に同じ。Haskell では型クラスインスタンスとして定義する。

**検証**: GHCi で `runParser jsonValue "{\"key\": [1, true, null]}"` をテスト。

#### Step 1.3c: JSON プリンター

**ファイル**: `src/StudyGroup/Json/Printer.hs`

```haskell
renderJson :: JsonValue -> String
```

- 再帰的に `JsonValue` を JSON 文字列に変換
- まず compact 出力、pretty-print は後回し

**検証**: `renderJson (parseJson input) == input` の往復テスト。

#### Step 1.3d: ドメイン型 ⇔ JSON エンコード/デコード

**ファイル**: `src/StudyGroup/Json/Encode.hs`

```haskell
appDataToJson :: AppData -> JsonValue
jsonToAppData :: JsonValue -> Maybe AppData

memberNameToString :: MemberName -> String
stringToMemberName :: String -> Maybe MemberName
```

- `Maybe` を使ったエラーハンドリング（パース失敗 → `Nothing`）
- `lookupField :: String -> [(String, JsonValue)] -> Maybe JsonValue` ヘルパー

**検証**: `jsonToAppData (appDataToJson sampleData) == Just sampleData` を確認。

---

### Step 1.4: ファイル永続化

**ファイル**: `src/StudyGroup/Storage.hs`

```haskell
loadData    :: FilePath -> IO AppData
saveData    :: FilePath -> AppData -> IO ()
defaultData :: AppData  -- 初期データ（しらおかさん・ノリさんの興味リスト）
```

- ファイルが存在しない場合 → `defaultData` を返す（`catchIOError` 使用）
- パース失敗時も `defaultData` にフォールバック
- データファイルパス: `data/study-group.json`

**検証**: `saveData` → `loadData` で同じデータが得られること。

---

### Step 1.5: ドメインロジック（純粋関数）

**ファイル**: `src/StudyGroup/Operations.hs`

```haskell
listInterests   :: MemberName -> AppData -> [Interest]
addInterest     :: MemberName -> String -> AppData -> AppData
removeInterest  :: MemberName -> String -> AppData -> AppData
listSessions    :: AppData -> [StudySession]
addSession      :: String -> String -> AppData -> AppData
listMembers     :: AppData -> [MemberName]
```

- **全て純粋関数**（IO なし）。`AppData` を受け取り新しい `AppData` を返す
- `filter` で削除、`(:)` で追加
- ロードマップ Phase 1「不変性と純粋関数」の実践

**検証**: GHCi で直接テスト可能（IO が絡まない）。

---

## Phase 2: HTTP サーバー

### Step 2.1: HTTP 型定義

**ファイル**: `src/StudyGroup/Http/Types.hs`

```haskell
data HttpMethod = GET | POST | DELETE
  deriving (Show, Eq)

data HttpRequest = HttpRequest
  { reqMethod  :: HttpMethod
  , reqPath    :: String
  , reqHeaders :: [(String, String)]
  , reqBody    :: String
  } deriving (Show)

data HttpStatus = Ok200 | Created201 | BadRequest400 | NotFound404 | MethodNotAllowed405
  deriving (Show)

data HttpResponse = HttpResponse
  { resStatus  :: HttpStatus
  , resHeaders :: [(String, String)]
  , resBody    :: String
  } deriving (Show)
```

---

### Step 2.2: HTTP リクエストパーサー

**ファイル**: `src/StudyGroup/Http/Parser.hs`

```haskell
parseRequest :: String -> Maybe HttpRequest
```

- 1行目を `words` で分割 → メソッド・パス取得
- ヘッダー行を `:` で分割して連想リスト化
- `Content-Length` ヘッダー分だけボディを読む
- `\r\n` の処理に注意（`\r` を `filter` で除去）

---

### Step 2.3: HTTP レスポンスビルダー

**ファイル**: `src/StudyGroup/Http/Response.hs`

```haskell
renderResponse :: HttpResponse -> String
jsonResponse   :: HttpStatus -> String -> HttpResponse
errorResponse  :: HttpStatus -> String -> HttpResponse
```

- `Content-Length` はバイト長で計算（UTF-8 マルチバイト対応の自前関数を用意）
- `\r\n` を明示的に付与

---

### Step 2.4: ルーティング

**ファイル**: `src/StudyGroup/Http/Router.hs`

```haskell
route :: HttpRequest -> AppData -> (HttpResponse, Maybe AppData)
```

パターンマッチでパス・メソッドを振り分け:

```haskell
route req appData = case (reqMethod req, splitPath (reqPath req)) of
  (GET,    ["members"])                          -> handleListMembers appData
  (GET,    ["members", name, "interests"])        -> handleListInterests name appData
  (POST,   ["members", name, "interests"])        -> handleAddInterest name (reqBody req) appData
  (DELETE, ["members", name, "interests", topic]) -> handleRemoveInterest name topic appData
  (GET,    ["sessions"])                          -> handleListSessions appData
  (POST,   ["sessions"])                          -> handleAddSession (reqBody req) appData
  _                                               -> (errorResponse NotFound404 "Not Found", Nothing)
```

**URL パスの方針**: 日本語はURLに入れず、ASCII 識別子（`shiraoka`, `nori`）を使う。`memberSlug :: MemberName -> String` 関数で URL 用 ID と表示名を分離。

- `Maybe AppData` でデータ変更の有無を表現（変更あり → `Just newData`、読み取りのみ → `Nothing`）

---

### Step 2.5: API ハンドラ

**ファイル**: `src/StudyGroup/Api/Handlers.hs`

```haskell
handleListMembers    :: AppData -> (HttpResponse, Maybe AppData)
handleListInterests  :: String -> AppData -> (HttpResponse, Maybe AppData)
handleAddInterest    :: String -> String -> AppData -> (HttpResponse, Maybe AppData)
handleRemoveInterest :: String -> String -> AppData -> (HttpResponse, Maybe AppData)
handleListSessions   :: AppData -> (HttpResponse, Maybe AppData)
handleAddSession     :: String -> AppData -> (HttpResponse, Maybe AppData)
```

- `Operations.hs` の純粋関数を呼び出し、`Json.Encode` で JSON に変換して `HttpResponse` を返す
- POST ボディは `Json.Parser` でパース
- エラーケースは `BadRequest400` を返す

---

### Step 2.6: サーバーメインループ

**ファイル**: `app/Server.hs`

- `IORef AppData` でサーバー起動中のデータをメモリに保持
- `forever` + `accept` のシングルスレッドループ（2人利用なので十分）
- データ変更時のみファイルに書き込み
- ソケットを `Handle` に変換して `hSetEncoding utf8` を設定（UTF-8 対応）

**検証**: `cabal run study-group-server` + `curl` で各エンドポイントを確認。

---

## Phase 3: CLI クライアント

### Step 3.1: コマンド型定義とパース

**ファイル**: `app/Client.hs`

```haskell
data Command
  = ListMembers
  | ListInterests (Maybe String)
  | AddInterest String String
  | RemoveInterest String String
  | ListSessions
  | AddSession String String

parseArgs :: [String] -> Maybe Command
```

`getArgs` + パターンマッチで引数を解釈。

### Step 3.2: HTTP クライアント

```haskell
sendRequest :: String -> Int -> HttpRequest -> IO String
```

- `Network.Socket` でサーバーに TCP 接続
- リクエスト送信 → レスポンス受信 → ボディ抽出

### Step 3.3: コマンド実行

```haskell
executeCommand :: Command -> IO ()
```

- 各 `Command` → 適切な HTTP リクエスト → レスポンスを人間が読みやすい形式で表示

**検証**: サーバー起動状態で CLI コマンドを実行。

---

## Phase 4: Docker & デプロイ

### Step 4.1: Dockerfile（マルチステージビルド）

- ビルドステージ: `haskell:9.6` で `cabal build`
- 実行ステージ: `debian:bookworm-slim` + `libgmp10` のみ

### Step 4.2: docker-compose.yml

- ポートマッピング: `8080:8080`
- データディレクトリのボリュームマウント: `./data:/data`

### Step 4.3: Google Cloud デプロイ

- Cloud Run を第一候補（低トラフィックなら無料枠内）
- ファイル永続化の課題: Cloud Storage（GCS）に読み書きするか、Compute Engine にするか検討

---

## 実装順序とテスト方法

| # | 対象 | テスト方法 |
|:--|:-----|:-----------|
| 1 | `study-group-app.cabal` + 空モジュール | `cabal build all` |
| 2 | `StudyGroup.Types` | GHCi で値の生成・表示 |
| 3 | `StudyGroup.Json.Types` | GHCi で `JsonValue` 生成 |
| 4 | `StudyGroup.Json.Parser` | GHCi で `runParser jsonValue "{...}"` |
| 5 | `StudyGroup.Json.Printer` | GHCi で往復テスト |
| 6 | `StudyGroup.Json.Encode` | GHCi で `appDataToJson` / `jsonToAppData` |
| 7 | `StudyGroup.Operations` | GHCi で純粋関数テスト |
| 8 | `StudyGroup.Storage` | GHCi で `saveData` → `loadData` |
| 9 | `StudyGroup.Http.Types` | 型定義のみ |
| 10 | `StudyGroup.Http.Parser` | GHCi でサンプルリクエストパース |
| 11 | `StudyGroup.Http.Response` | GHCi でレスポンス文字列生成 |
| 12 | `StudyGroup.Http.Router` + `Api.Handlers` | GHCi でルーティングテスト |
| 13 | `app/Server.hs` | `cabal run study-group-server` + `curl` |
| 14 | `app/Client.hs` | `cabal run study-group -- interests list` |
| 15 | `Dockerfile` + `docker-compose.yml` | `docker compose up` |

---

## 各ステップの Haskell 学習ポイント

| ステップ | 主な学習概念 |
|:---------|:-------------|
| Types.hs | 代数的データ型、レコード構文、deriving |
| Json/Parser.hs | **最重要**: newtype、型クラスインスタンス（Functor/Applicative/Alternative）、パーサーコンビネータ、高階関数 |
| Operations.hs | 純粋関数、`filter`/`map`、不変データの変換 |
| Storage.hs | IO モナド、`do` 構文、エラーハンドリング |
| Http/Router.hs | パターンマッチ、タプル、ワイルドカード |
| Server.hs | IORef、ソケットIO、`forever` |
| Client.hs | `getArgs`、コマンドライン引数のパターンマッチ |

---

## 注意すべき技術的課題

1. **UTF-8 エンコーディング**: ソケットを `Handle` に変換して `hSetEncoding utf8` を設定するのが最も簡単
2. **Content-Length**: `String` の `length` はコードポイント数であり UTF-8 バイト長ではない。自前で UTF-8 バイト長を計算する純粋関数を用意する
3. **HTTP ボディ読み取り**: `Content-Length` 分だけ正確に読む必要がある（`hGetContents` は不適切）
4. **同時接続**: シングルスレッドで問題ないが、`close` 前に `hFlush` でデータ送信を保証する
