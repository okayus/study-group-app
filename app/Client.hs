module Main where

import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, hSetEncoding, stderr, stdout, utf8)
import Control.Exception (catch, SomeException)
import Data.List (isInfixOf)

import StudyGroup.Cli (parseArgs, executeCommand)

-- | CLI エントリポイント。
-- 処理フロー:
--   1. getArgs でコマンドライン引数を取得
--   2. ヘルプ要求 (引数なし / -h / --help / help) ならそのまま usage を表示して正常終了
--   3. それ以外は parseArgs で Command に変換し、認識できなければ usage + 異常終了
--   4. 認識できれば executeCommand を実行 (例外は catch でハンドリング)
main :: IO ()
main = do
  -- コンテナ等の locale が C / POSIX のとき、stdout のデフォルトエンコーディングが
  -- ASCII になり、API レスポンスに含まれる日本語 (例: "ノリさん") を putStrLn
  -- しようとした瞬間に commitBuffer: invalid argument で落ちる。
  -- 実行環境の locale に依存しないよう、ここで UTF-8 を強制する。
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
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
-- 例外メッセージに接続失敗系のキーワードが含まれているときだけ
-- 「サーバー起動してる?」のヒントを添える。それ以外の例外
-- (エンコーディング不整合・JSON パース失敗など) ではヒントを出さない。
-- 全ての例外を「サーバー未起動」に丸めると、無関係なバグを誤誘導してしまう。
handleError :: SomeException -> IO ()
handleError e = do
  let msg = show e
  hPutStrLn stderr ("Error: " ++ msg)
  if isConnectionError msg
    then hPutStrLn stderr "Is the API server running? Start it with: docker compose up --build"
    else return ()
  exitFailure

-- | 例外メッセージが API サーバーへの接続失敗っぽいか判定する。
-- http-client の例外は接続できない場合 "ConnectionFailure" / "Connection refused"
-- を含むため、それをキーワードに判定する。
-- ※ "HttpExceptionRequest" は ResponseTimeout など接続成功後の異常も含めて
-- 全 HTTP 例外に出る文字列なので判定キーワードに入れない。入れてしまうと
-- 「サーバーは生きているが応答が返らない」ケースまで「サーバー未起動」と
-- 誤誘導してしまう。
isConnectionError :: String -> Bool
isConnectionError msg =
  any (`isInfixOf` msg)
    [ "ConnectionFailure"
    , "Connection refused"
    ]
