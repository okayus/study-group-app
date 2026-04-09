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

-- | リクエストをルーティングしてレスポンスを返す
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

-- | GET /members
handleGetMembers :: IORef AppData -> IO HttpResponse
handleGetMembers ref = do
  appData <- readIORef ref
  let members = listMembers appData
      json = JsonArray (map (JsonString . memberNameToString) members)
  return $ jsonResponse Ok200 (renderJson json)

-- | GET /members/:name/interests
handleGetInterests :: IORef AppData -> String -> IO HttpResponse
handleGetInterests ref nameStr =
  case stringToMemberName nameStr of
    Nothing -> return $ errorResponse NotFound404 ("Unknown member: " ++ nameStr)
    Just member -> do
      appData <- readIORef ref
      let interests = listInterests member appData
          json = JsonArray (map interestToJson interests)
      return $ jsonResponse Ok200 (renderJson json)

-- | POST /members/:name/interests
--   ボディ: {"topic": "..."}
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

-- | DELETE /members/:name/interests/:topic
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

-- | GET /sessions
handleGetSessions :: IORef AppData -> IO HttpResponse
handleGetSessions ref = do
  appData <- readIORef ref
  let sessions = listSessions appData
      json = JsonArray (map sessionToJson sessions)
  return $ jsonResponse Ok200 (renderJson json)

-- | POST /sessions
--   ボディ: {"date": "YYYY-MM-DD", "topic": "..."}
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

-- | JSON オブジェクトから "topic" フィールドを取得
extractTopic :: JsonValue -> Maybe String
extractTopic (JsonObject fields) =
  case lookup "topic" fields of
    Just (JsonString t) -> Just t
    _                   -> Nothing
extractTopic _ = Nothing

-- | JSON オブジェクトから "date" と "topic" フィールドを取得
extractDateAndTopic :: JsonValue -> Maybe (String, String)
extractDateAndTopic (JsonObject fields) = do
  JsonString date  <- lookup "date" fields
  JsonString topic <- lookup "topic" fields
  Just (date, topic)
extractDateAndTopic _ = Nothing

-- | URL パーセントデコード（日本語トピック名の DELETE 対応）
decodeURIComponent :: String -> String
decodeURIComponent [] = []
decodeURIComponent ('%':h1:h2:rest) =
  case hexToChar h1 h2 of
    Nothing -> '%' : decodeURIComponent (h1:h2:rest)
    Just c  -> c : decodeURIComponent rest
decodeURIComponent ('+':rest) = ' ' : decodeURIComponent rest
decodeURIComponent (c:rest) = c : decodeURIComponent rest

hexToChar :: Char -> Char -> Maybe Char
hexToChar h1 h2 = do
  d1 <- hexDigit h1
  d2 <- hexDigit h2
  Just (toEnum (d1 * 16 + d2))

hexDigit :: Char -> Maybe Int
hexDigit c
  | c >= '0' && c <= '9' = Just (fromEnum c - fromEnum '0')
  | c >= 'a' && c <= 'f' = Just (fromEnum c - fromEnum 'a' + 10)
  | c >= 'A' && c <= 'F' = Just (fromEnum c - fromEnum 'A' + 10)
  | otherwise             = Nothing
