module StudyGroup.Http.Server
  ( runServer
  ) where

import Network.Socket
  ( Socket
  , AddrInfo(..)
  , SocketType(Stream)
  , defaultHints
  , getAddrInfo
  , socket
  , bind
  , listen
  , accept
  , close
  , setSocketOption
  , SocketOption(ReuseAddr)
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
import Control.Exception (bracket, bracketOnError, catch, SomeException)

import StudyGroup.Http.Types (HttpRequest, HttpResponse, HttpStatus(..))
import StudyGroup.Http.Parser (parseRequest)
import StudyGroup.Http.Response (renderResponse, errorResponse)

-- | TCP ソケットで HTTP サーバーを起動し、リクエストを待ち受ける。
-- ハンドラー関数を引数に取る高階関数設計により、
-- ソケット管理（この関数）とビジネスロジック（ハンドラー）が疎結合になる。
--
-- 処理フロー:
--   1. getAddrInfo で 0.0.0.0:port のアドレス情報を取得
--   2. openSocket でソケットを作成・バインド・リッスン
--   3. acceptLoop で接続を受け付けるループに入る
--   4. bracket で異常終了時もソケットを確実に close する
runServer :: Int -> (HttpRequest -> IO HttpResponse) -> IO ()
runServer port handler = do
  let hints = defaultHints { addrSocketType = Stream }
  addr:_ <- getAddrInfo (Just hints) (Just "0.0.0.0") (Just (show port))
  bracket (openSocket addr) close $ \sock -> do
    putStrLn $ "Server running on port " ++ show port
    acceptLoop sock handler

-- | アドレス情報からサーバーソケットを作成し、バインド・リッスンする。
-- bracketOnError により、バインドやリッスンで例外が発生した場合も
-- ソケットが確実に close される（リソースリーク防止）。
-- ReuseAddr を設定して、サーバー再起動時に "Address already in use" を防ぐ。
-- listen のバックログ 5 は、同時接続待ちキューの最大数。
openSocket :: AddrInfo -> IO Socket
openSocket addr = bracketOnError
  (socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr))
  close
  (\sock -> do
    setSocketOption sock ReuseAddr 1
    bind sock (addrAddress addr)
    listen sock 5
    return sock
  )

-- | 接続を受け付ける無限ループ。
-- accept でクライアント接続をブロッキング待機し、
-- handleClient でリクエストを処理する。
-- 1クライアントの処理中に例外が発生しても catch で捕捉してログ出力し、
-- ループを継続する（1リクエストの失敗がサーバー全体を停止させない）。
-- 末尾再帰でループを実現（Haskell ではループ構文を使わない）。
acceptLoop :: Socket -> (HttpRequest -> IO HttpResponse) -> IO ()
acceptLoop serverSock handler = do
  (clientSock, _clientAddr) <- accept serverSock
  handleClient clientSock handler
    `catch` (\e -> putStrLn $ "Error: " ++ show (e :: SomeException))
  acceptLoop serverSock handler

-- | 1つのクライアント接続を処理する。
-- socketToHandle でソケットを Handle に変換し、System.IO の関数で読み書きする。
-- Handle 化する理由:
--   - base の System.IO 関数が使える（bytestring パッケージへの依存を回避）
--   - hSetEncoding で UTF-8 を設定でき、日本語を正しく扱える
-- NoBuffering にする理由: レスポンスを即座に送信するため。
-- 処理後は hClose でソケットも含めてクリーンアップされる。
handleClient :: Socket -> (HttpRequest -> IO HttpResponse) -> IO ()
handleClient sock handler = do
  hdl <- socketToHandle sock ReadWriteMode
  hSetEncoding hdl utf8
  hSetBuffering hdl NoBuffering
  raw <- readRequest hdl
  resp <- case parseRequest raw of
    Nothing  -> return $ errorResponse BadRequest400 "Invalid HTTP request"
    Just req -> handler req
  hPutStr hdl (renderResponse resp)
  hFlush hdl
  hClose hdl

-- | HTTP リクエスト全体を Handle から読み取る。
-- 2段階で読む:
--   1. readUntilHeaderEnd: ヘッダー終端 \r\n\r\n が来るまで読む
--   2. Content-Length があれば、ヘッダー後に続くボディの残り「バイト数」を読む
--
-- Content-Length は UTF-8 の「バイト数」なので、Char 単位ではなく
-- 各 Char を UTF-8 にしたときのバイト幅を加算して比較する必要がある。
-- 旧クライアント（自作）は length（Char 数）で Content-Length を出していたため
-- たまたま整合していたが、http-client 等の正しい実装は必ずバイトで送ってくる。
readRequest :: Handle -> IO String
readRequest hdl = do
  headers <- readUntilHeaderEnd hdl ""
  let contentLen = findContentLength headers
  case contentLen of
    Nothing  -> return headers
    Just len -> do
      let bodyStart = dropHeaderEnd headers
          alreadyReadBytes = utf8ByteLength bodyStart
          remaining = len - alreadyReadBytes
      if remaining <= 0
        then return headers
        else do
          moreBody <- readExactBytes hdl remaining
          return (headers ++ moreBody)

-- | 文字列を UTF-8 でエンコードしたときのバイト数を計算する。
-- Response 側の utf8ByteLength と同じロジックを Server モジュール内で
-- 自己完結させる（Server から Response への依存を増やさない設計判断）。
utf8ByteLength :: String -> Int
utf8ByteLength = sum . map charLen
  where
    charLen c
      | cp <= 0x7F   = 1
      | cp <= 0x7FF  = 2
      | cp <= 0xFFFF = 3
      | otherwise    = 4
      where cp = fromEnum c

-- | \r\n\r\n（ヘッダー終端）が見つかるまで1文字ずつ読む。
-- 文字を逆順で蓄積（cons で先頭に追加 = O(1)）し、完了時に reverse する。
-- 1文字ずつ読む理由: ヘッダー終端を正確に検出するため。
-- バッファリングすると \r\n\r\n が読み取りチャンクの境界をまたぐケースの
-- 処理が複雑化する。パフォーマンスよりシンプルさを優先した設計判断。
readUntilHeaderEnd :: Handle -> String -> IO String
readUntilHeaderEnd hdl acc = do
  eof <- hIsEOF hdl
  if eof
    then return (reverse acc)
    else do
      c <- hGetChar hdl
      let acc' = c : acc
      if endsWithCRLFCRLF acc'
        then return (reverse acc')
        else readUntilHeaderEnd hdl acc'

-- | 逆順に蓄積された文字列が \r\n\r\n で終わっているか判定する。
-- acc は逆順なので、先頭4文字が \n\r\n\r なら元の文字列は \r\n\r\n で終わる。
-- パターンマッチで効率的に判定（文字列比較やリスト操作なし）。
endsWithCRLFCRLF :: String -> Bool
endsWithCRLFCRLF ('\n':'\r':'\n':'\r':_) = True
endsWithCRLFCRLF _                        = False

-- | Handle から指定したバイト数ぶん UTF-8 文字を読み取る。
-- Handle は UTF-8 モードなので hGetChar が 1〜4 バイトをまとめて 1 Char に
-- 変換する。残りバイト数を「読み取った Char の UTF-8 バイト幅」で減算して
-- ループする。
-- EOF に達したら途中で切り上げる（クライアントが途中で切断した場合の安全策）。
readExactBytes :: Handle -> Int -> IO String
readExactBytes _ n | n <= 0 = return ""
readExactBytes hdl n = do
  eof <- hIsEOF hdl
  if eof
    then return ""
    else do
      c <- hGetChar hdl
      let used = charUtf8Bytes c
      rest <- readExactBytes hdl (n - used)
      return (c : rest)
  where
    charUtf8Bytes c
      | cp <= 0x7F   = 1
      | cp <= 0x7FF  = 2
      | cp <= 0xFFFF = 3
      | otherwise    = 4
      where cp = fromEnum c

-- | 文字列から \r\n\r\n 以降の部分（ボディの開始部分）を取得する。
-- readUntilHeaderEnd がヘッダー終端を含めて読み取るので、
-- ヘッダー部分を読み飛ばしてボディだけを取り出す。
dropHeaderEnd :: String -> String
dropHeaderEnd ('\r':'\n':'\r':'\n':rest) = rest
dropHeaderEnd (_:xs) = dropHeaderEnd xs
dropHeaderEnd []     = ""

-- | HTTP ヘッダー文字列から Content-Length の値を探す。
-- ヘッダー文字列を行に分割し、"content-length" で始まる行を探す。
-- ヘッダー名は case-insensitive なので小文字に変換して比較する。
-- 見つかったらコロン以降の数値をパースして Just Int で返す。
-- Content-Length がなければ Nothing（ボディなしリクエスト）。
findContentLength :: String -> Maybe Int
findContentLength str =
  case filter isContentLength (rawLines str) of
    []    -> Nothing
    (l:_) -> parseIntAfterColon l
  where
    -- ヘッダー名の先頭14文字を小文字化して "content-length" と比較
    isContentLength line =
      let lower = map toLowerChar (take 15 line)
      in take 14 lower == "content-length"

    -- CRLF で行分割する（lines' と同様だが、Server モジュール内で自己完結させる）
    rawLines :: String -> [String]
    rawLines "" = []
    rawLines s  = let (l, rest) = breakLine s in l : rawLines rest

    -- 改行で文字列を分割
    breakLine :: String -> (String, String)
    breakLine "" = ("", "")
    breakLine ('\r':'\n':rest) = ("", rest)
    breakLine ('\n':rest)      = ("", rest)
    breakLine (c:rest)         = let (l, r) = breakLine rest in (c:l, r)

    -- "Content-Length: 42" からコロン以降の数値をパース
    parseIntAfterColon :: String -> Maybe Int
    parseIntAfterColon s =
      case dropWhile (/= ':') s of
        []    -> Nothing
        (_:r) -> readMaybeInt (dropWhile (== ' ') (stripCR r))

    -- 末尾の \r を除去
    stripCR "" = ""
    stripCR s
      | last s == '\r' = init s
      | otherwise      = s

-- | 文字列を安全に Int に変換する。
-- reads は Haskell 標準の安全なパース関数で、
-- 文字列全体が整数として読めた場合のみ Just を返す。
-- "42" → Just 42、"42abc" → Nothing、"" → Nothing
readMaybeInt :: String -> Maybe Int
readMaybeInt s =
  case reads s of
    [(n, "")] -> Just n
    _         -> Nothing

-- | ASCII 文字1文字を小文字に変換する。
-- findContentLength でヘッダー名を正規化するために使用。
toLowerChar :: Char -> Char
toLowerChar c
  | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
  | otherwise             = c
