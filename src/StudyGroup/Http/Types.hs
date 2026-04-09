module StudyGroup.Http.Types
  ( HttpMethod(..)
  , HttpRequest(..)
  , HttpResponse(..)
  , HttpStatus(..)
  , statusCode
  , statusMessage
  ) where

-- | HTTP メソッド
data HttpMethod = GET | POST | DELETE | OPTIONS
  deriving (Show, Eq)

-- | HTTP リクエスト（パース済み）
data HttpRequest = HttpRequest
  { requestMethod  :: HttpMethod
  , requestPath    :: String        -- e.g. "/members/nori/interests"
  , requestHeaders :: [(String, String)]
  , requestBody    :: String
  } deriving (Show, Eq)

-- | HTTP ステータス
data HttpStatus
  = Ok200
  | Created201
  | NoContent204
  | BadRequest400
  | NotFound404
  | MethodNotAllowed405
  | InternalError500
  deriving (Show, Eq)

statusCode :: HttpStatus -> Int
statusCode Ok200              = 200
statusCode Created201         = 201
statusCode NoContent204       = 204
statusCode BadRequest400      = 400
statusCode NotFound404        = 404
statusCode MethodNotAllowed405 = 405
statusCode InternalError500   = 500

statusMessage :: HttpStatus -> String
statusMessage Ok200              = "OK"
statusMessage Created201         = "Created"
statusMessage NoContent204       = "No Content"
statusMessage BadRequest400      = "Bad Request"
statusMessage NotFound404        = "Not Found"
statusMessage MethodNotAllowed405 = "Method Not Allowed"
statusMessage InternalError500   = "Internal Server Error"

-- | HTTP レスポンス
data HttpResponse = HttpResponse
  { responseStatus  :: HttpStatus
  , responseHeaders :: [(String, String)]
  , responseBody    :: String
  } deriving (Show, Eq)
