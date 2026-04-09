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

-- | サーバーを起動して接続を待ち受ける
runServer :: Int -> (HttpRequest -> IO HttpResponse) -> IO ()
runServer port handler = do
  let hints = defaultHints { addrSocketType = Stream }
  addr:_ <- getAddrInfo (Just hints) (Just "0.0.0.0") (Just (show port))
  bracket (openSocket addr) close $ \sock -> do
    putStrLn $ "Server running on port " ++ show port
    acceptLoop sock handler

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

-- | 接続を受け付けるループ
acceptLoop :: Socket -> (HttpRequest -> IO HttpResponse) -> IO ()
acceptLoop serverSock handler = do
  (clientSock, _clientAddr) <- accept serverSock
  handleClient clientSock handler
    `catch` (\e -> putStrLn $ "Error: " ++ show (e :: SomeException))
  acceptLoop serverSock handler

-- | クライアント接続を処理（Handle 経由で読み書き）
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

-- | HTTP リクエスト全体を読み取る
--   ヘッダーを \r\n\r\n まで読み、Content-Length があればボディも読む
readRequest :: Handle -> IO String
readRequest hdl = do
  headers <- readUntilHeaderEnd hdl ""
  let contentLen = findContentLength headers
  case contentLen of
    Nothing  -> return headers
    Just len -> do
      let bodyStart = dropHeaderEnd headers
          alreadyRead = length bodyStart
          remaining = len - alreadyRead
      if remaining <= 0
        then return headers
        else do
          moreBody <- readExact hdl remaining
          return (headers ++ moreBody)

-- | \r\n\r\n が見つかるまで1文字ずつ読む
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

-- | 蓄積された逆順文字列が \r\n\r\n で終わるか
endsWithCRLFCRLF :: String -> Bool
endsWithCRLFCRLF ('\n':'\r':'\n':'\r':_) = True
endsWithCRLFCRLF _                        = False

-- | 指定文字数を正確に読む
readExact :: Handle -> Int -> IO String
readExact _ 0 = return ""
readExact hdl n = do
  eof <- hIsEOF hdl
  if eof
    then return ""
    else do
      c <- hGetChar hdl
      rest <- readExact hdl (n - 1)
      return (c : rest)

-- | ヘッダー終端以降（ボディ部分）を取得
dropHeaderEnd :: String -> String
dropHeaderEnd ('\r':'\n':'\r':'\n':rest) = rest
dropHeaderEnd (_:xs) = dropHeaderEnd xs
dropHeaderEnd []     = ""

-- | Content-Length ヘッダーの値を探す
findContentLength :: String -> Maybe Int
findContentLength str =
  case filter isContentLength (rawLines str) of
    []    -> Nothing
    (l:_) -> parseIntAfterColon l
  where
    isContentLength line =
      let lower = map toLowerChar (take 15 line)
      in take 14 lower == "content-length"

    rawLines :: String -> [String]
    rawLines "" = []
    rawLines s  = let (l, rest) = breakLine s in l : rawLines rest

    breakLine :: String -> (String, String)
    breakLine "" = ("", "")
    breakLine ('\r':'\n':rest) = ("", rest)
    breakLine ('\n':rest)      = ("", rest)
    breakLine (c:rest)         = let (l, r) = breakLine rest in (c:l, r)

    parseIntAfterColon :: String -> Maybe Int
    parseIntAfterColon s =
      case dropWhile (/= ':') s of
        []    -> Nothing
        (_:r) -> readMaybeInt (dropWhile (== ' ') (stripCR r))

    stripCR "" = ""
    stripCR s
      | last s == '\r' = init s
      | otherwise      = s

-- | 安全な Int 読み取り
readMaybeInt :: String -> Maybe Int
readMaybeInt s =
  case reads s of
    [(n, "")] -> Just n
    _         -> Nothing

toLowerChar :: Char -> Char
toLowerChar c
  | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
  | otherwise             = c
