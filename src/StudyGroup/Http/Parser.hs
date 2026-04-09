module StudyGroup.Http.Parser
  ( parseRequest
  ) where

import StudyGroup.Http.Types
  ( HttpMethod(..)
  , HttpRequest(..)
  )

-- | 生の HTTP リクエスト文字列をパースする
--
-- 対応形式:
--   GET /path HTTP/1.1\r\n
--   Header-Name: value\r\n
--   \r\n
--   body
parseRequest :: String -> Maybe HttpRequest
parseRequest raw =
  case lines' raw of
    []       -> Nothing
    (requestLine : rest) ->
      case parseRequestLine requestLine of
        Nothing           -> Nothing
        Just (method, path) ->
          let (headerLines, body) = splitHeadersBody rest
              headers = parseHeaders headerLines
          in Just HttpRequest
               { requestMethod  = method
               , requestPath    = path
               , requestHeaders = headers
               , requestBody    = body
               }

-- | リクエストライン "GET /path HTTP/1.1" をパース
parseRequestLine :: String -> Maybe (HttpMethod, String)
parseRequestLine line =
  case words' line of
    [methodStr, path, _version] ->
      case parseMethod methodStr of
        Nothing     -> Nothing
        Just method -> Just (method, path)
    _ -> Nothing

parseMethod :: String -> Maybe HttpMethod
parseMethod "GET"     = Just GET
parseMethod "POST"    = Just POST
parseMethod "DELETE"  = Just DELETE
parseMethod "OPTIONS" = Just OPTIONS
parseMethod _         = Nothing

-- | ヘッダー行とボディを分離（空行で区切る）
splitHeadersBody :: [String] -> ([String], String)
splitHeadersBody = go []
  where
    go acc []     = (reverse acc, "")
    go acc (l:ls)
      | isBlank l = (reverse acc, unlines' ls)
      | otherwise = go (l : acc) ls

    isBlank ""   = True
    isBlank "\r" = True
    isBlank _    = False

-- | ヘッダー行 "Name: value" をパース
parseHeaders :: [String] -> [(String, String)]
parseHeaders = foldr (\l acc -> case parseHeader l of
                                  Just h  -> h : acc
                                  Nothing -> acc) []

parseHeader :: String -> Maybe (String, String)
parseHeader line =
  case breakOn ':' line of
    Nothing       -> Nothing
    Just (name, rest) ->
      let value = dropWhile (== ' ') (stripCR rest)
      in Just (toLowerStr (stripCR name), value)

-- | \r\n ベースの行分割
lines' :: String -> [String]
lines' "" = []
lines' s  =
  let (line, rest) = breakOnNewline s
  in line : lines' rest

breakOnNewline :: String -> (String, String)
breakOnNewline "" = ("", "")
breakOnNewline ('\r':'\n':rest) = ("", rest)
breakOnNewline ('\n':rest)      = ("", rest)
breakOnNewline (c:rest) =
  let (line, remainder) = breakOnNewline rest
  in (c : line, remainder)

unlines' :: [String] -> String
unlines' []     = ""
unlines' [x]    = x
unlines' (x:xs) = x ++ "\n" ++ unlines' xs

-- | 文字で文字列を分割（最初の出現位置）
breakOn :: Char -> String -> Maybe (String, String)
breakOn _ "" = Nothing
breakOn c (x:xs)
  | x == c    = Just ("", xs)
  | otherwise  = case breakOn c xs of
                   Nothing       -> Nothing
                   Just (before, after) -> Just (x : before, after)

-- | 空白区切り
words' :: String -> [String]
words' s = case dropWhile (== ' ') s of
  "" -> []
  s' -> let (w, rest) = break (== ' ') s'
        in w : words' rest

-- | 末尾の \r を除去
stripCR :: String -> String
stripCR "" = ""
stripCR s
  | last s == '\r' = init s
  | otherwise      = s

-- | 小文字変換（ASCII のみ）
toLowerStr :: String -> String
toLowerStr = map toLowerChar

toLowerChar :: Char -> Char
toLowerChar c
  | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
  | otherwise             = c
