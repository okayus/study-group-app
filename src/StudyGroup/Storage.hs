module StudyGroup.Storage
  ( loadData
  , saveData
  , defaultData
  , dataFilePath
  ) where

import System.IO (hSetEncoding, utf8, IOMode(..), hGetContents, hPutStr, withFile)
import System.IO.Error (catchIOError)
import StudyGroup.Types
  ( MemberName(..)
  , Interest(..)
  , AppData(..)
  )
import StudyGroup.Json.Parser (parseJson)
import StudyGroup.Json.Printer (renderJson)
import StudyGroup.Json.Encode (appDataToJson, jsonToAppData)

-- | データファイルパス
dataFilePath :: FilePath
dataFilePath = "data/study-group.json"

-- | 初期データ（overview.md に記載のメンバーの興味リスト）
defaultData :: AppData
defaultData = AppData
  { appInterests =
      [ Interest Shiraoka "関数型プログラミング"
      , Interest Shiraoka "セキュリティ（アプリケーション、OSなど、徳丸本）"
      , Interest Shiraoka "Rust"
      , Interest Shiraoka "UIデザイン"
      , Interest Nori "関数型プログラミング"
      , Interest Nori "Rust"
      , Interest Nori "AIエージェントをうまく動かす部分"
      , Interest Nori "Agent Skills"
      , Interest Nori "アルゴリズム"
      , Interest Nori "コンピュータサイエンス"
      ]
  , appSessions = []
  }

-- | データをファイルから読み込む
loadData :: FilePath -> IO AppData
loadData path = catchIOError readAndParse handleError
  where
    readAndParse = do
      contents <- readFileStrict path
      case parseJson contents >>= jsonToAppData of
        Just appData -> return appData
        Nothing      -> return defaultData

    handleError _ = return defaultData

    readFileStrict :: FilePath -> IO String
    readFileStrict p = withFile p ReadMode $ \h -> do
      hSetEncoding h utf8
      content <- hGetContents h
      -- force evaluation before handle is closed
      let len = length content
      seq len (return content)

-- | データをファイルに保存する。
-- writeFile はロケール依存のエンコーダを使うため、コンテナのロケールが
-- POSIX/C のような ASCII 系だと日本語トピック等を書く瞬間に
-- "invalid argument (invalid character)" 例外で書き込み途中に落ちる。
-- loadData と同じく明示的に Handle を UTF-8 に設定して書き込むことで
-- ロケール非依存にする。
saveData :: FilePath -> AppData -> IO ()
saveData path appData = do
  let json = renderJson (appDataToJson appData)
  withFile path WriteMode $ \h -> do
    hSetEncoding h utf8
    hPutStr h json
