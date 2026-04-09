module Main where

import System.Environment (getArgs)
import System.Exit (exitFailure)
import Control.Exception (catch, SomeException)

import StudyGroup.Cli (parseArgs, executeCommand)

-- | CLI エントリポイント。
-- 処理フロー:
--   1. getArgs でコマンドライン引数を取得
--   2. parseArgs でパターンマッチにより Command に変換
--   3. executeCommand で API サーバーにリクエストを送信し結果を表示
--
-- 引数が認識できなければ使い方を表示して終了する。
-- API サーバーへの接続失敗等の例外は catch で捕捉し、
-- ユーザーにわかりやすいエラーメッセージを表示する。
main :: IO ()
main = do
  args <- getArgs
  case parseArgs args of
    Nothing -> do
      printUsage
      exitFailure
    Just cmd ->
      executeCommand cmd
        `catch` handleError

-- | 使い方を表示する。
-- 不正な引数が渡された場合に呼ばれる。
-- 全コマンドの書式を一覧で表示し、ユーザーが正しい引数を知れるようにする。
printUsage :: IO ()
printUsage = do
  putStrLn "Usage: study-group <command>"
  putStrLn ""
  putStrLn "Commands:"
  putStrLn "  interests list [NAME]        Show interests (all members or specific member)"
  putStrLn "  interests add NAME TOPIC     Add an interest"
  putStrLn "  interests remove NAME TOPIC  Remove an interest"
  putStrLn "  sessions list                Show study sessions"
  putStrLn "  sessions add DATE TOPIC      Add a study session"
  putStrLn ""
  putStrLn "Examples:"
  putStrLn "  study-group interests list"
  putStrLn "  study-group interests list nori"
  putStrLn "  study-group interests add nori Rust"
  putStrLn "  study-group interests remove nori Rust"
  putStrLn "  study-group sessions list"
  putStrLn "  study-group sessions add 2026-04-16 \"HTTP server\""

-- | 例外を捕捉してエラーメッセージを表示する。
-- API サーバーが起動していない場合に接続エラーが発生するため、
-- そのケースをユーザーにわかりやすく案内する。
handleError :: SomeException -> IO ()
handleError e = do
  putStrLn $ "Error: " ++ show e
  putStrLn "Is the API server running? Start it with: cabal run study-group-server"
