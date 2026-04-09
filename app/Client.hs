module Main where

import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Control.Exception (catch, SomeException)

import StudyGroup.Cli (parseArgs, executeCommand)

-- | CLI エントリポイント。
-- 処理フロー:
--   1. getArgs でコマンドライン引数を取得
--   2. ヘルプ要求 (引数なし / -h / --help / help) ならそのまま usage を表示して正常終了
--   3. それ以外は parseArgs で Command に変換し、認識できなければ usage + 異常終了
--   4. 認識できれば executeCommand を実行 (例外は catch でハンドリング)
main :: IO ()
main = do
  args <- getArgs
  if isHelpRequest args
    then printUsage
    else case parseArgs args of
      Nothing -> do
        hPutStrLn stderr ("Unknown command: " ++ unwords args)
        printUsage
        exitFailure
      Just cmd ->
        executeCommand cmd
          `catch` handleError

-- | 引数がヘルプ要求かどうか判定する。
-- 引数なし、または `-h` / `--help` / `help` のいずれか単独で渡された場合に True。
-- これらは「正常な使い方」として扱い、usage を stdout に出して終了コード 0 で抜ける。
isHelpRequest :: [String] -> Bool
isHelpRequest []         = True
isHelpRequest ["-h"]     = True
isHelpRequest ["--help"] = True
isHelpRequest ["help"]   = True
isHelpRequest _          = False

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
