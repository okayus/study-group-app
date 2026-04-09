module StudyGroup.Json.Parser
  ( parseJson
  , Parser(..)
  ) where

import Control.Applicative (Alternative(..))
import Data.Char (isDigit, isSpace)
import StudyGroup.Json.Types (JsonValue(..))

-- | パーサーコンビネータの基盤型
newtype Parser a = Parser { runParser :: String -> Maybe (a, String) }

instance Functor Parser where
  fmap f (Parser p) = Parser $ \input ->
    case p input of
      Nothing        -> Nothing
      Just (a, rest) -> Just (f a, rest)

instance Applicative Parser where
  pure a = Parser $ \input -> Just (a, input)
  (Parser pf) <*> (Parser pa) = Parser $ \input ->
    case pf input of
      Nothing        -> Nothing
      Just (f, rest) -> case pa rest of
        Nothing         -> Nothing
        Just (a, rest') -> Just (f a, rest')

instance Alternative Parser where
  empty = Parser $ \_ -> Nothing
  (Parser p1) <|> (Parser p2) = Parser $ \input ->
    case p1 input of
      Nothing -> p2 input
      result  -> result

-- Monad instance for sequencing with bind
instance Monad Parser where
  (Parser p) >>= f = Parser $ \input ->
    case p input of
      Nothing        -> Nothing
      Just (a, rest) -> runParser (f a) rest

-- | 基本パーサー群

-- 1文字マッチ
charP :: Char -> Parser Char
charP c = Parser $ \input ->
  case input of
    (x:xs) | x == c -> Just (c, xs)
    _               -> Nothing

-- 条件を満たす文字を0個以上消費
spanP :: (Char -> Bool) -> Parser String
spanP predicate = Parser $ \input ->
  let (matched, rest) = span predicate input
  in Just (matched, rest)

-- 空白読み飛ばし
ws :: Parser String
ws = spanP isSpace

-- 文字列マッチ
stringP :: String -> Parser String
stringP = traverse charP

-- セパレータ区切り
sepBy :: Parser a -> Parser b -> Parser [a]
sepBy element sep = (:) <$> element <*> many (sep *> element) <|> pure []

-- | JSON パーサー群

jsonNull :: Parser JsonValue
jsonNull = JsonNull <$ stringP "null"

jsonBool :: Parser JsonValue
jsonBool = (JsonBool True <$ stringP "true")
       <|> (JsonBool False <$ stringP "false")

jsonNumber :: Parser JsonValue
jsonNumber = Parser $ \input ->
  let (neg, rest0) = case input of
        ('-':xs) -> ("-", xs)
        _        -> ("", input)
      (intPart, rest1) = span isDigit rest0
  in if null intPart
     then Nothing
     else case rest1 of
       ('.':rest2) ->
         let (fracPart, rest3) = span isDigit rest2
         in if null fracPart
            then Just (JsonNumber (read (neg ++ intPart)), rest1)
            else Just (JsonNumber (read (neg ++ intPart ++ "." ++ fracPart)), rest3)
       _ -> Just (JsonNumber (read (neg ++ intPart)), rest1)

jsonString :: Parser JsonValue
jsonString = JsonString <$> stringLiteral

stringLiteral :: Parser String
stringLiteral = charP '"' *> innerString <* charP '"'
  where
    innerString :: Parser String
    innerString = Parser $ \input -> Just (go input [])

    go :: String -> String -> (String, String)
    go [] acc = (reverse acc, [])
    go ('\\':c:rest) acc = case c of
      '"'  -> go rest ('"' : acc)
      '\\' -> go rest ('\\' : acc)
      '/'  -> go rest ('/' : acc)
      'n'  -> go rest ('\n' : acc)
      'r'  -> go rest ('\r' : acc)
      't'  -> go rest ('\t' : acc)
      _    -> go rest (c : '\\' : acc)
    go ('"':rest) acc = (reverse acc, '"' : rest)
    go (c:rest) acc = go rest (c : acc)

jsonArray :: Parser JsonValue
jsonArray = JsonArray <$>
  (charP '[' *> ws *> elements <* ws <* charP ']')
  where
    elements = sepBy (ws *> jsonValue <* ws) (charP ',')

jsonObject :: Parser JsonValue
jsonObject = JsonObject <$>
  (charP '{' *> ws *> pairs <* ws <* charP '}')
  where
    pairs = sepBy pair (charP ',')
    pair = (\k _ v -> (k, v)) <$>
      (ws *> stringLiteral <* ws) <*>
      charP ':' <*>
      (ws *> jsonValue <* ws)

jsonValue :: Parser JsonValue
jsonValue = jsonNull <|> jsonBool <|> jsonNumber <|> jsonString <|> jsonArray <|> jsonObject

-- | JSON 文字列をパースする
parseJson :: String -> Maybe JsonValue
parseJson input = case runParser (ws *> jsonValue <* ws) input of
  Just (value, []) -> Just value
  _                -> Nothing
