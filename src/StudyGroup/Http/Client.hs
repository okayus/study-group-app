module StudyGroup.Http.Client
  ( sendRequest
  , renderRequest
  ) where

import Network.Socket
  ( AddrInfo(..)
  , SocketType(Stream)
  , defaultHints
  , getAddrInfo
  , socket
  , connect
  , socketToHandle
  )
import System.IO
  ( Handle
  , hSetEncoding
  , utf8
  , hSetBuffering
  , BufferMode(NoBuffering)
  , hGetChar
  , hPutStr
  , hFlush
  , hClose
  , hIsEOF
  , IOMode(ReadWriteMode)
  )
import Control.Exception (bracket)

import StudyGroup.Http.Types (HttpMethod(..), HttpRequest(..))

-- | HTTP リクエストをサーバーに送信し、レスポンスボディを返す。
-- Network.Socket で TCP 接続を確立し、HTTP リクエストを送信、
-- レスポンスを受信してボディ部分だけを抽出する。
-- bracket でソケットのクリーンアップを保証する。
--
-- 処理フロー:
--   1. getAddrInfo でサーバーのアドレスを解決
--   2. socket で TCP ソケットを作成し connect で接続
--   3. socketToHandle で Handle 化し UTF-8 を設定
--   4. HTTP リクエスト文字列を送信
--   5. レスポンスを受信してヘッダーとボディに分割
--   6. ボディ部分を返す
sendRequest :: String -> Int -> HttpRequest -> IO String
sendRequest host port req = do
  let hints = defaultHints { addrSocketType = Stream }
  addr:_ <- getAddrInfo (Just hints) (Just host) (Just (show port))
  bracket (openConnection addr) hClose $ \hdl -> do
    hPutStr hdl (renderRequest host port req)
    hFlush hdl
    response <- readResponse hdl
    return (extractBody response)

-- | アドレス情報から TCP 接続を確立し Handle を返す。
-- socket → connect → socketToHandle の3ステップ。
-- UTF-8 エンコーディングと NoBuffering を設定する理由は
-- Server.hs の handleClient と同様。
openConnection :: AddrInfo -> IO Handle
openConnection addr = do
  sock <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
  connect sock (addrAddress addr)
  hdl <- socketToHandle sock ReadWriteMode
  hSetEncoding hdl utf8
  hSetBuffering hdl NoBuffering
  return hdl

-- | HttpRequest を HTTP/1.1 準拠のリクエスト文字列にレンダリングする。
-- サーバー側の renderResponse と対になるクライアント側の関数。
-- Host ヘッダーは HTTP/1.1 で必須。
-- Content-Length はボディがある場合のみ付与する。
-- Connection: close で接続をレスポンス後に閉じるよう指示し、
-- クライアント側でレスポンス終端を EOF で検出できるようにする。
renderRequest :: String -> Int -> HttpRequest -> String
renderRequest host port req =
  let method = showMethod (requestMethod req)
      path   = requestPath req
      body   = requestBody req
      requestLine = method ++ " " ++ path ++ " HTTP/1.1\r\n"
      hostHeader  = "Host: " ++ host ++ ":" ++ show port ++ "\r\n"
      connHeader  = "Connection: close\r\n"
      bodyHeaders = if null body
                    then ""
                    else "Content-Type: application/json\r\n"
                      ++ "Content-Length: " ++ show (length body) ++ "\r\n"
  in requestLine ++ hostHeader ++ connHeader ++ bodyHeaders ++ "\r\n" ++ body

-- | HttpMethod を HTTP メソッド文字列に変換する。
-- Http.Types の Show インスタンスと同じ出力だが、
-- show に依存すると将来 Show の実装が変わった場合に壊れるため、
-- 明示的にマッピングする。
showMethod :: HttpMethod -> String
showMethod GET     = "GET"
showMethod POST    = "POST"
showMethod DELETE  = "DELETE"
showMethod OPTIONS = "OPTIONS"

-- | Handle からレスポンス全体を EOF まで読み取る。
-- Connection: close を送信しているため、サーバーはレスポンス送信後に
-- 接続を閉じる。EOF まで読めばレスポンス全体を取得できる。
-- 1文字ずつ読む理由は Server.hs と同様（シンプルさ優先）。
readResponse :: Handle -> IO String
readResponse hdl = do
  eof <- hIsEOF hdl
  if eof
    then return ""
    else do
      c <- hGetChar hdl
      rest <- readResponse hdl
      return (c : rest)

-- | HTTP レスポンス文字列からボディ部分を抽出する。
-- ヘッダーとボディは \r\n\r\n で区切られている。
-- この区切りを見つけて以降の部分をボディとして返す。
-- 区切りが見つからない場合は空文字列を返す。
extractBody :: String -> String
extractBody ('\r':'\n':'\r':'\n':rest) = rest
extractBody (_:xs) = extractBody xs
extractBody []     = ""
