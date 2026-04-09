module Main where

import Data.IORef (newIORef)
import System.IO (hSetEncoding, stderr, stdout, utf8)
import StudyGroup.Storage (loadData, dataFilePath)
import StudyGroup.Http.Server (runServer)
import StudyGroup.Api (handleRequest)

-- | API サーバーのエントリポイント。
-- 処理フロー:
--   1. loadData でファイルからアプリケーションデータを読み込む
--      （ファイルが無い or パース失敗時は defaultData にフォールバック）
--   2. IORef にデータを格納（インメモリ状態管理）
--   3. runServer でポート 8080 で TCP サーバーを起動
--   4. 各リクエストは handleRequest に委譲される
--
-- IORef を使う理由:
--   リクエストごとにファイルを読み直すのは非効率なので、
--   メモリ上にデータを保持し、変更時のみファイルに書き出す。
main :: IO ()
main = do
  -- コンテナ等で locale が C / POSIX のとき、ログ中の日本語が
  -- commitBuffer: invalid argument で落ちないように UTF-8 を強制する。
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  putStrLn "Loading data..."
  appData <- loadData dataFilePath
  ref <- newIORef appData
  putStrLn "Starting study-group-server on port 8080"
  runServer 8080 (handleRequest ref)
