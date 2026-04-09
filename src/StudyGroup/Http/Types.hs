module StudyGroup.Http.Types
  ( HttpMethod(..)
  , HttpRequest(..)
  , HttpResponse(..)
  , HttpStatus(..)
  , statusCode
  , statusMessage
  ) where

-- | HTTP メソッド
-- GET/POST/DELETE/OPTIONS の4種を ADT で表現。
-- 文字列のまま扱うと typo がランタイムエラーになるが、
-- ADT にすればコンパイル時に不正な値を排除できる。
-- OPTIONS は将来の CORS 対応用に含めている。
data HttpMethod = GET | POST | DELETE | OPTIONS
  deriving (Show, Eq)

-- | HTTP リクエスト（パース済み）
-- 生の HTTP 文字列を構造化した型。
-- パーサーがこの型を生成し、以降の処理は文字列操作から解放される。
-- requestHeaders はキー名を小文字正規化済み（HTTP ヘッダーは case-insensitive）。
data HttpRequest = HttpRequest
  { requestMethod  :: HttpMethod
  , requestPath    :: String        -- e.g. "/members/nori/interests"
  , requestHeaders :: [(String, String)]
  , requestBody    :: String
  } deriving (Show, Eq)

-- | HTTP ステータス
-- ステータスコードを ADT で表現することで、
-- statusCode / statusMessage でのパターンマッチに網羅性チェックが効く。
-- 新しいステータスを追加したとき、コンパイラが対応漏れを教えてくれる。
data HttpStatus
  = Ok200
  | Created201
  | NoContent204
  | BadRequest400
  | NotFound404
  | MethodNotAllowed405
  | InternalError500
  deriving (Show, Eq)

-- | HttpStatus → 数値ステータスコード
-- レスポンスのステータスライン "HTTP/1.1 200 OK" の数値部分に使う。
statusCode :: HttpStatus -> Int
statusCode Ok200              = 200
statusCode Created201         = 201
statusCode NoContent204       = 204
statusCode BadRequest400      = 400
statusCode NotFound404        = 404
statusCode MethodNotAllowed405 = 405
statusCode InternalError500   = 500

-- | HttpStatus → 英語のステータスメッセージ
-- レスポンスのステータスライン "HTTP/1.1 200 OK" のメッセージ部分に使う。
statusMessage :: HttpStatus -> String
statusMessage Ok200              = "OK"
statusMessage Created201         = "Created"
statusMessage NoContent204       = "No Content"
statusMessage BadRequest400      = "Bad Request"
statusMessage NotFound404        = "Not Found"
statusMessage MethodNotAllowed405 = "Method Not Allowed"
statusMessage InternalError500   = "Internal Server Error"

-- | HTTP レスポンス
-- ハンドラーが返す構造化されたレスポンス。
-- renderResponse でこの型から HTTP プロトコル準拠の文字列に変換する。
-- responseHeaders は Content-Type 等のアプリケーション固有ヘッダー。
-- Content-Length は renderResponse が自動付与するので含めなくてよい。
data HttpResponse = HttpResponse
  { responseStatus  :: HttpStatus
  , responseHeaders :: [(String, String)]
  , responseBody    :: String
  } deriving (Show, Eq)
