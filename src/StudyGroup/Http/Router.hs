module StudyGroup.Http.Router
  ( Route(..)
  , PathPattern(..)
  , matchRoute
  , splitPath
  ) where

import StudyGroup.Http.Types (HttpMethod(..))

-- | パスパターンの各セグメントを表す型。
-- Literal はパスの固定部分（"members", "interests" 等）にマッチし、
-- Capture はパス内の動的部分（":name", ":topic" 等）を名前付きでキャプチャする。
-- 現在 Api.hs ではパターンマッチで直接ルーティングしているため未使用だが、
-- ルート定義を宣言的に書きたい場合の拡張ポイントとして提供している。
data PathPattern
  = Literal String    -- 固定文字列にマッチ (e.g. "members")
  | Capture String    -- 任意の文字列をキャプチャ (e.g. ":name")
  deriving (Show, Eq)

-- | ルート定義を表す型。
-- HTTP メソッドとパスパターンの組み合わせで1つのエンドポイントを表現する。
-- 例: Route GET [Literal "members", Capture "name", Literal "interests"]
--   → GET /members/:name/interests
data Route = Route
  { routeMethod  :: HttpMethod
  , routePattern :: [PathPattern]
  } deriving (Show, Eq)

-- | リクエストのメソッドとパスがルート定義にマッチするか判定する。
-- マッチした場合、Capture で捕捉された値を [(パラメータ名, 値)] で返す。
-- メソッドが異なれば即座に Nothing を返す（メソッド不一致は頻出なので先に判定）。
matchRoute :: Route -> HttpMethod -> String -> Maybe [(String, String)]
matchRoute route method path
  | routeMethod route /= method = Nothing
  | otherwise = matchSegments (routePattern route) (splitPath path)

-- | パスパターンのリストとパスセグメントのリストを再帰的に照合する。
-- 両方が同時に空になればマッチ成功。片方だけ残ったらマッチ失敗。
-- 各セグメントのマッチ結果（キャプチャ値）を結合して返す。
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

-- | パスパターン1つとパスセグメント1つを照合する。
-- Literal: 文字列が完全一致すればマッチ（キャプチャなし）。
-- Capture: 任意の文字列にマッチし、(パラメータ名, 実際の値) をキャプチャする。
matchSegment :: PathPattern -> String -> Maybe [(String, String)]
matchSegment (Literal expected) actual
  | expected == actual = Just []
  | otherwise          = Nothing
matchSegment (Capture name) actual = Just [(name, actual)]

-- | URL パスをスラッシュ区切りのセグメントリストに分割する。
-- 先頭・末尾のスラッシュや連続スラッシュによる空セグメントは除去する。
-- 例: "/members/nori/interests" → ["members", "nori", "interests"]
--     "/sessions/"              → ["sessions"]
-- Api.hs のパターンマッチで (method, splitPath path) のタプルとして使われる。
splitPath :: String -> [String]
splitPath = filter (not . null) . splitOn '/'

-- | 指定した区切り文字で文字列を分割する。
-- splitPath の内部実装。break で区切り文字を探し、再帰的に分割する。
-- 例: splitOn '/' "a/b/c" → ["a", "b", "c"]
splitOn :: Char -> String -> [String]
splitOn _ "" = [""]
splitOn sep s =
  let (before, rest) = break (== sep) s
  in before : case rest of
       []     -> []
       (_:xs) -> splitOn sep xs
