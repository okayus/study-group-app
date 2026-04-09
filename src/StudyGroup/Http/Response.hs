module StudyGroup.Http.Response
  ( renderResponse
  , jsonResponse
  , errorResponse
  , noContentResponse
  ) where

import StudyGroup.Http.Types
  ( HttpResponse(..)
  , HttpStatus(..)
  , statusCode
  , statusMessage
  )

-- | HttpResponse を HTTP レスポンス文字列にレンダリング
renderResponse :: HttpResponse -> String
renderResponse resp =
  let status = responseStatus resp
      line = "HTTP/1.1 " ++ show (statusCode status) ++ " " ++ statusMessage status ++ "\r\n"
      hdrs = concatMap renderHeader (responseHeaders resp)
      body = responseBody resp
      contentLength = "Content-Length: " ++ show (length body) ++ "\r\n"
  in line ++ hdrs ++ contentLength ++ "\r\n" ++ body

renderHeader :: (String, String) -> String
renderHeader (name, value) = name ++ ": " ++ value ++ "\r\n"

-- | JSON レスポンスを組み立てる
jsonResponse :: HttpStatus -> String -> HttpResponse
jsonResponse status body = HttpResponse
  { responseStatus  = status
  , responseHeaders = [("Content-Type", "application/json; charset=utf-8")]
  , responseBody    = body
  }

-- | エラーレスポンス（JSON 形式）
errorResponse :: HttpStatus -> String -> HttpResponse
errorResponse status msg = jsonResponse status $
  "{\"error\":\"" ++ escapeJsonStr msg ++ "\"}"

-- | 204 No Content レスポンス
noContentResponse :: HttpResponse
noContentResponse = HttpResponse
  { responseStatus  = NoContent204
  , responseHeaders = []
  , responseBody    = ""
  }

-- | JSON 文字列エスケープ（簡易版）
escapeJsonStr :: String -> String
escapeJsonStr = concatMap escapeChar
  where
    escapeChar '"'  = "\\\""
    escapeChar '\\' = "\\\\"
    escapeChar '\n' = "\\n"
    escapeChar c    = [c]
