module StudyGroup.Http.Router
  ( Route(..)
  , PathPattern(..)
  , matchRoute
  , splitPath
  ) where

import StudyGroup.Http.Types (HttpMethod(..))

-- | パスパターンの各セグメント
data PathPattern
  = Literal String    -- 固定文字列にマッチ (e.g. "members")
  | Capture String    -- 任意の文字列をキャプチャ (e.g. ":name")
  deriving (Show, Eq)

-- | ルート定義
data Route = Route
  { routeMethod  :: HttpMethod
  , routePattern :: [PathPattern]
  } deriving (Show, Eq)

-- | リクエストのメソッドとパスがルートにマッチするか判定
--   マッチした場合、キャプチャされた値を [(パラメータ名, 値)] で返す
matchRoute :: Route -> HttpMethod -> String -> Maybe [(String, String)]
matchRoute route method path
  | routeMethod route /= method = Nothing
  | otherwise = matchSegments (routePattern route) (splitPath path)

matchSegments :: [PathPattern] -> [String] -> Maybe [(String, String)]
matchSegments [] []         = Just []
matchSegments [] _          = Nothing
matchSegments _  []         = Nothing
matchSegments (p:ps) (s:ss) =
  case matchSegment p s of
    Nothing      -> Nothing
    Just capture ->
      case matchSegments ps ss of
        Nothing      -> Nothing
        Just captures -> Just (capture ++ captures)

matchSegment :: PathPattern -> String -> Maybe [(String, String)]
matchSegment (Literal expected) actual
  | expected == actual = Just []
  | otherwise          = Nothing
matchSegment (Capture name) actual = Just [(name, actual)]

-- | URL パスをセグメントに分割
--   "/members/nori/interests" -> ["members", "nori", "interests"]
splitPath :: String -> [String]
splitPath = filter (not . null) . splitOn '/'

splitOn :: Char -> String -> [String]
splitOn _ "" = [""]
splitOn sep s =
  let (before, rest) = break (== sep) s
  in before : case rest of
       []     -> []
       (_:xs) -> splitOn sep xs
