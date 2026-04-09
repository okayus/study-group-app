module StudyGroup.Api
  ( handleRequest
  ) where

import Data.IORef (IORef, readIORef, writeIORef)

import StudyGroup.Types
  ( Interest(..)
  , AppData(..)
  )
import StudyGroup.Operations
  ( listMembers
  , listInterests
  , addInterest
  , removeInterest
  , listSessions
  , addSession
  )
import StudyGroup.Storage (saveData, dataFilePath)
import StudyGroup.Json.Types (JsonValue(..))
import StudyGroup.Json.Parser (parseJson)
import StudyGroup.Json.Printer (renderJson)
import StudyGroup.Json.Encode
  ( memberNameToString
  , stringToMemberName
  , interestToJson
  , sessionToJson
  )
import StudyGroup.Http.Types
  ( HttpMethod(..)
  , HttpRequest(..)
  , HttpResponse(..)
  , HttpStatus(..)
  )
import StudyGroup.Http.Response
  ( jsonResponse
  , errorResponse
  , noContentResponse
  )
import StudyGroup.Http.Router (splitPath)

-- | リクエストをルーティングしてレスポンスを返す。
-- (メソッド, パスセグメントのリスト) のタプルをパターンマッチで振り分ける。
-- Haskell のパターンマッチによる宣言的ルーティング:
--   - コンパイラが網羅性をチェックしてくれる
--   - ルート定義と処理の対応が一目で分かる
--   - どのパターンにもマッチしなければ 404 を返す
--
-- IORef AppData を受け取り、状態の読み書きとファイル永続化を行う。
-- 単一スレッド前提のため排他制御は未実装。
handleRequest :: IORef AppData -> HttpRequest -> IO HttpResponse
handleRequest ref req =
  case (requestMethod req, splitPath (requestPath req)) of
    -- GET /members
    (GET, ["members"]) ->
      handleGetMembers ref

    -- GET /members/:name/interests
    (GET, ["members", name, "interests"]) ->
      handleGetInterests ref name

    -- POST /members/:name/interests
    (POST, ["members", name, "interests"]) ->
      handleAddInterest ref name (requestBody req)

    -- DELETE /members/:name/interests/:topic
    (DELETE, ["members", name, "interests", topic]) ->
      handleDeleteInterest ref name (decodeURIComponent topic)

    -- GET /sessions
    (GET, ["sessions"]) ->
      handleGetSessions ref

    -- POST /sessions
    (POST, ["sessions"]) ->
      handleAddSession ref (requestBody req)

    -- 404
    _ ->
      return $ errorResponse NotFound404 "Not found"

-- | GET /members — メンバー一覧を JSON 配列で返す。
-- Operations.listMembers で全メンバーを取得し、
-- 各 MemberName を文字列に変換して JsonArray にする。
-- レスポンス例: ["shiraoka","nori"]
handleGetMembers :: IORef AppData -> IO HttpResponse
handleGetMembers ref = do
  appData <- readIORef ref
  let members = listMembers appData
      json = JsonArray (map (JsonString . memberNameToString) members)
  return $ jsonResponse Ok200 (renderJson json)

-- | GET /members/:name/interests — 指定メンバーの興味リストを JSON 配列で返す。
-- パスの :name 部分を stringToMemberName で MemberName に変換し、
-- 該当するメンバーの興味リストをフィルタして返す。
-- 存在しないメンバー名なら 404 を返す。
-- レスポンス例: [{"member":"nori","topic":"Rust"},...]
handleGetInterests :: IORef AppData -> String -> IO HttpResponse
handleGetInterests ref nameStr =
  case stringToMemberName nameStr of
    Nothing -> return $ errorResponse NotFound404 ("Unknown member: " ++ nameStr)
    Just member -> do
      appData <- readIORef ref
      let interests = listInterests member appData
          json = JsonArray (map interestToJson interests)
      return $ jsonResponse Ok200 (renderJson json)

-- | POST /members/:name/interests — 興味を追加する。
-- リクエストボディ {"topic": "..."} から topic を抽出し、
-- Operations.addInterest で重複チェック付きで追加する。
-- 追加後は IORef を更新し、ファイルにも永続化する。
-- 201 Created で追加した興味の JSON を返す。
-- メンバー名不正 → 404、ボディ不正 → 400。
handleAddInterest :: IORef AppData -> String -> String -> IO HttpResponse
handleAddInterest ref nameStr body =
  case stringToMemberName nameStr of
    Nothing -> return $ errorResponse NotFound404 ("Unknown member: " ++ nameStr)
    Just member ->
      case parseJson body >>= extractTopic of
        Nothing -> return $ errorResponse BadRequest400 "Invalid body: expected {\"topic\": \"...\"}"
        Just topic -> do
          appData <- readIORef ref
          let newData = addInterest member topic appData
          writeIORef ref newData
          saveData dataFilePath newData
          let newInterest = Interest member topic
          return $ jsonResponse Created201 (renderJson (interestToJson newInterest))

-- | DELETE /members/:name/interests/:topic — 興味を削除する。
-- パスの :topic 部分は URL エンコードされている可能性があるため、
-- decodeURIComponent でデコードしてから削除処理を行う。
-- Operations.removeInterest でフィルタリング削除し、IORef とファイルを更新。
-- 204 No Content を返す（ボディなし）。
-- 指定したトピックが存在しない場合も 204 を返す（冪等性）。
handleDeleteInterest :: IORef AppData -> String -> String -> IO HttpResponse
handleDeleteInterest ref nameStr topic =
  case stringToMemberName nameStr of
    Nothing -> return $ errorResponse NotFound404 ("Unknown member: " ++ nameStr)
    Just member -> do
      appData <- readIORef ref
      let newData = removeInterest member topic appData
      writeIORef ref newData
      saveData dataFilePath newData
      return noContentResponse

-- | GET /sessions — 勉強会予定一覧を JSON 配列で返す。
-- Operations.listSessions で全セッションを取得し、JSON 配列にする。
-- レスポンス例: [{"date":"2026-04-16","topic":"HTTP server"}]
handleGetSessions :: IORef AppData -> IO HttpResponse
handleGetSessions ref = do
  appData <- readIORef ref
  let sessions = listSessions appData
      json = JsonArray (map sessionToJson sessions)
  return $ jsonResponse Ok200 (renderJson json)

-- | POST /sessions — 勉強会予定を追加する。
-- リクエストボディ {"date": "YYYY-MM-DD", "topic": "..."} から
-- date と topic を抽出し、Operations.addSession で先頭に追加する。
-- 追加後は IORef とファイルを更新し、201 Created で追加したセッションの JSON を返す。
-- ボディ不正 → 400。
handleAddSession :: IORef AppData -> String -> IO HttpResponse
handleAddSession ref body =
  case parseJson body >>= extractDateAndTopic of
    Nothing -> return $ errorResponse BadRequest400 "Invalid body: expected {\"date\": \"...\", \"topic\": \"...\"}"
    Just (date, topic) -> do
      appData <- readIORef ref
      let newData = addSession date topic appData
      writeIORef ref newData
      saveData dataFilePath newData
      return $ jsonResponse Created201 (renderJson (sessionToJson (head (appSessions newData))))

-- | JSON オブジェクトから "topic" フィールドの文字列値を取得する。
-- POST /members/:name/interests のボディパースに使う。
-- JsonObject 以外や topic フィールドが文字列でない場合は Nothing。
extractTopic :: JsonValue -> Maybe String
extractTopic (JsonObject fields) =
  case lookup "topic" fields of
    Just (JsonString t) -> Just t
    _                   -> Nothing
extractTopic _ = Nothing

-- | JSON オブジェクトから "date" と "topic" フィールドの文字列値を取得する。
-- POST /sessions のボディパースに使う。
-- do 記法で Maybe モナドを連鎖し、どちらか一方でも欠けていれば Nothing を返す。
extractDateAndTopic :: JsonValue -> Maybe (String, String)
extractDateAndTopic (JsonObject fields) = do
  JsonString date  <- lookup "date" fields
  JsonString topic <- lookup "topic" fields
  Just (date, topic)
extractDateAndTopic _ = Nothing

-- | URL パーセントエンコードされた文字列をデコードする。
-- DELETE /members/:name/interests/:topic で日本語トピック名が
-- %E3%83%86%E3%82%B9%E3%83%88 のようにエンコードされて送られるため、
-- 元の文字列に復元する必要がある。
-- '%' + 16進2桁 → 対応する文字に変換。'+' → 空白。それ以外はそのまま。
-- UTF-8 のマルチバイト文字はバイト単位でデコードされ、
-- Haskell の Char 型（Unicode コードポイント）に変換される。
decodeURIComponent :: String -> String
decodeURIComponent [] = []
decodeURIComponent ('%':h1:h2:rest) =
  case hexToChar h1 h2 of
    Nothing -> '%' : decodeURIComponent (h1:h2:rest)
    Just c  -> c : decodeURIComponent rest
decodeURIComponent ('+':rest) = ' ' : decodeURIComponent rest
decodeURIComponent (c:rest) = c : decodeURIComponent rest

-- | 16進数2桁を Char に変換する。
-- 2つの16進数字をそれぞれ数値に変換し、上位4ビット + 下位4ビットを合成して
-- toEnum で Char にする。どちらかの桁が無効な16進数字なら Nothing。
hexToChar :: Char -> Char -> Maybe Char
hexToChar h1 h2 = do
  d1 <- hexDigit h1
  d2 <- hexDigit h2
  Just (toEnum (d1 * 16 + d2))

-- | 16進数字1文字を数値 (0-15) に変換する。
-- '0'-'9' → 0-9、'a'-'f' / 'A'-'F' → 10-15。
-- 16進数字以外は Nothing。
hexDigit :: Char -> Maybe Int
hexDigit c
  | c >= '0' && c <= '9' = Just (fromEnum c - fromEnum '0')
  | c >= 'a' && c <= 'f' = Just (fromEnum c - fromEnum 'a' + 10)
  | c >= 'A' && c <= 'F' = Just (fromEnum c - fromEnum 'A' + 10)
  | otherwise             = Nothing
