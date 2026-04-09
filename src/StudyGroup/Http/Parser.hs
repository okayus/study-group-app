module StudyGroup.Http.Parser
  ( parseRequest
  ) where

import StudyGroup.Http.Types
  ( HttpMethod(..)
  , HttpRequest(..)
  )

-- | 生の HTTP リクエスト文字列をパースして HttpRequest に変換する。
-- HTTP/1.1 の基本形式に対応:
--   GET /path HTTP/1.1\r\n
--   Header-Name: value\r\n
--   \r\n
--   body
--
-- パース失敗時は Nothing を返す（不正なリクエストに対して安全に 400 を返すため）。
-- 処理手順:
--   1. CRLF で行分割
--   2. 先頭行（リクエストライン）からメソッドとパスを抽出
--   3. 空行までをヘッダー行、空行以降をボディとして分離
--   4. ヘッダー行を (名前, 値) のペアにパース
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

-- | リクエストライン "GET /path HTTP/1.1" をパースする。
-- 空白区切りで3トークン（メソッド・パス・バージョン）に分割し、
-- メソッドを HttpMethod に変換する。バージョンは無視（HTTP/1.0 も受け入れる）。
parseRequestLine :: String -> Maybe (HttpMethod, String)
parseRequestLine line =
  case words' line of
    [methodStr, path, _version] ->
      case parseMethod methodStr of
        Nothing     -> Nothing
        Just method -> Just (method, path)
    _ -> Nothing

-- | メソッド文字列を HttpMethod に変換する。
-- 対応していないメソッド（PUT, PATCH 等）は Nothing を返す。
parseMethod :: String -> Maybe HttpMethod
parseMethod "GET"     = Just GET
parseMethod "POST"    = Just POST
parseMethod "DELETE"  = Just DELETE
parseMethod "OPTIONS" = Just OPTIONS
parseMethod _         = Nothing

-- | 行のリストをヘッダー部とボディ部に分離する。
-- HTTP では空行（CRLF のみの行）がヘッダーとボディの境界。
-- アキュムレータパターンで空行を探し、見つかったら残りをボディとして返す。
splitHeadersBody :: [String] -> ([String], String)
splitHeadersBody = go []
  where
    go acc []     = (reverse acc, "")
    go acc (l:ls)
      | isBlank l = (reverse acc, unlines' ls)
      | otherwise = go (l : acc) ls

    -- 空行の判定: 空文字列 or \r のみ（CRLF の \n は行分割で除去済み）
    isBlank ""   = True
    isBlank "\r" = True
    isBlank _    = False

-- | ヘッダー行のリストを (名前, 値) ペアのリストに変換する。
-- パースに失敗した行は単純にスキップする（foldr で畳み込み）。
parseHeaders :: [String] -> [(String, String)]
parseHeaders = foldr (\l acc -> case parseHeader l of
                                  Just h  -> h : acc
                                  Nothing -> acc) []

-- | 個別のヘッダー行 "Name: value" をパースする。
-- 最初の ':' でキーと値を分離し、値の先頭空白を除去する。
-- キー名は小文字に正規化する（HTTP ヘッダー名は case-insensitive なので、
-- 後続の検索処理で統一的に比較できるようにする）。
parseHeader :: String -> Maybe (String, String)
parseHeader line =
  case breakOn ':' line of
    Nothing       -> Nothing
    Just (name, rest) ->
      let value = dropWhile (== ' ') (stripCR rest)
      in Just (toLowerStr (stripCR name), value)

-- | \r\n ベースの行分割を行う。
-- Prelude の lines は \n のみ対応だが、HTTP は CRLF (\r\n) が標準。
-- \r\n と \n の両方に対応する自前実装。
lines' :: String -> [String]
lines' "" = []
lines' s  =
  let (line, rest) = breakOnNewline s
  in line : lines' rest

-- | 改行位置で文字列を分割する。
-- \r\n（CRLF）を優先的にマッチし、\n 単体にもフォールバックする。
-- 先頭から1文字ずつ走査し、改行を見つけたら (行, 残り) を返す。
breakOnNewline :: String -> (String, String)
breakOnNewline "" = ("", "")
breakOnNewline ('\r':'\n':rest) = ("", rest)
breakOnNewline ('\n':rest)      = ("", rest)
breakOnNewline (c:rest) =
  let (line, remainder) = breakOnNewline rest
  in (c : line, remainder)

-- | 行のリストを改行区切りで結合する。
-- Prelude の unlines は末尾に \n を付加するが、
-- HTTP ボディでは末尾の余計な改行を付けたくないため自前実装。
unlines' :: [String] -> String
unlines' []     = ""
unlines' [x]    = x
unlines' (x:xs) = x ++ "\n" ++ unlines' xs

-- | 指定文字の最初の出現位置で文字列を2つに分割する。
-- "Content-Type: application/json" を ':' で分割すると
-- ("Content-Type", " application/json") になる。
-- 見つからなければ Nothing を返す。
breakOn :: Char -> String -> Maybe (String, String)
breakOn _ "" = Nothing
breakOn c (x:xs)
  | x == c    = Just ("", xs)
  | otherwise  = case breakOn c xs of
                   Nothing       -> Nothing
                   Just (before, after) -> Just (x : before, after)

-- | 空白区切りで文字列をトークンに分割する。
-- Prelude の words と同等だが、明示的に空白文字 ' ' のみを区切りとする。
-- リクエストライン "GET /path HTTP/1.1" の分割に使う。
words' :: String -> [String]
words' s = case dropWhile (== ' ') s of
  "" -> []
  s' -> let (w, rest) = break (== ' ') s'
        in w : words' rest

-- | 末尾の \r を除去する。
-- CRLF を \n で行分割した後、行末に \r が残ることがあるため、
-- ヘッダーの名前・値から余分な \r を取り除く。
stripCR :: String -> String
stripCR "" = ""
stripCR s
  | last s == '\r' = init s
  | otherwise      = s

-- | ASCII 文字列を小文字に変換する。
-- HTTP ヘッダー名の正規化に使用。
-- Unicode の大文字小文字変換は不要（ヘッダー名は ASCII のみ）。
toLowerStr :: String -> String
toLowerStr = map toLowerChar

-- | ASCII 文字1文字を小文字に変換する。
-- 'A'(65) ~ 'Z'(90) に 32 を加算して 'a'(97) ~ 'z'(122) にする。
toLowerChar :: Char -> Char
toLowerChar c
  | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
  | otherwise             = c
