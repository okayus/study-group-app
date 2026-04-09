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

-- | HttpResponse を HTTP/1.1 準拠のレスポンス文字列にレンダリングする。
-- 出力形式:
--   HTTP/1.1 200 OK\r\n
--   Content-Type: application/json\r\n
--   Content-Length: 42\r\n
--   \r\n
--   {"key":"value"}
--
-- Content-Length はボディの文字数から自動計算して付与する。
-- これがないとクライアントがボディの読み取り完了を判断できない。
renderResponse :: HttpResponse -> String
renderResponse resp =
  let status = responseStatus resp
      line = "HTTP/1.1 " ++ show (statusCode status) ++ " " ++ statusMessage status ++ "\r\n"
      hdrs = concatMap renderHeader (responseHeaders resp)
      body = responseBody resp
      contentLength = "Content-Length: " ++ show (length body) ++ "\r\n"
  in line ++ hdrs ++ contentLength ++ "\r\n" ++ body

-- | ヘッダー1行を "Name: value\r\n" 形式にレンダリングする。
renderHeader :: (String, String) -> String
renderHeader (name, value) = name ++ ": " ++ value ++ "\r\n"

-- | JSON レスポンスを組み立てるヘルパー。
-- Content-Type: application/json; charset=utf-8 を自動付与する。
-- API ハンドラーが毎回ヘッダーを指定する冗長さを排除するための共通パターン。
jsonResponse :: HttpStatus -> String -> HttpResponse
jsonResponse status body = HttpResponse
  { responseStatus  = status
  , responseHeaders = [("Content-Type", "application/json; charset=utf-8")]
  , responseBody    = body
  }

-- | エラーレスポンスを JSON 形式で組み立てるヘルパー。
-- {"error": "メッセージ"} の形式で返す。
-- エラーメッセージは JSON 文字列エスケープされるので、
-- 任意の文字列を安全に埋め込める。
errorResponse :: HttpStatus -> String -> HttpResponse
errorResponse status msg = jsonResponse status $
  "{\"error\":\"" ++ escapeJsonStr msg ++ "\"}"

-- | 204 No Content レスポンス（DELETE 成功時に使う定数値）。
-- ボディもヘッダーも空。ステータスコードだけで成功を表現する。
noContentResponse :: HttpResponse
noContentResponse = HttpResponse
  { responseStatus  = NoContent204
  , responseHeaders = []
  , responseBody    = ""
  }

-- | JSON 文字列内の特殊文字をエスケープする。
-- errorResponse で使う簡易版。
-- Json.Printer.escapeString と同様だが、このモジュールは Json に依存しないため
-- 独立した実装を持つ（依存関係を最小限に保つ設計判断）。
escapeJsonStr :: String -> String
escapeJsonStr = concatMap escapeChar
  where
    escapeChar '"'  = "\\\""
    escapeChar '\\' = "\\\\"
    escapeChar '\n' = "\\n"
    escapeChar c    = [c]
