module StudyGroup.Json.Printer
  ( renderJson
  ) where

import StudyGroup.Json.Types (JsonValue(..))

-- | JsonValue を JSON 文字列にレンダリング（compact 形式）
renderJson :: JsonValue -> String
renderJson JsonNull       = "null"
renderJson (JsonBool b)   = if b then "true" else "false"
renderJson (JsonNumber n)
  | isInteger n = show (round n :: Integer)
  | otherwise   = show n
  where
    isInteger x = x == fromIntegral (round x :: Integer)
renderJson (JsonString s) = "\"" ++ escapeString s ++ "\""
renderJson (JsonArray xs) = "[" ++ intercalateComma (map renderJson xs) ++ "]"
renderJson (JsonObject kvs) = "{" ++ intercalateComma (map renderPair kvs) ++ "}"
  where
    renderPair (k, v) = "\"" ++ escapeString k ++ "\":" ++ renderJson v

-- | 文字列のエスケープ
escapeString :: String -> String
escapeString = concatMap escapeChar
  where
    escapeChar '"'  = "\\\""
    escapeChar '\\' = "\\\\"
    escapeChar '\n' = "\\n"
    escapeChar '\r' = "\\r"
    escapeChar '\t' = "\\t"
    escapeChar c    = [c]

-- | カンマ区切り結合
intercalateComma :: [String] -> String
intercalateComma []     = ""
intercalateComma [x]    = x
intercalateComma (x:xs) = x ++ "," ++ intercalateComma xs
