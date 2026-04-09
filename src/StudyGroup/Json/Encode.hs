module StudyGroup.Json.Encode
  ( appDataToJson
  , jsonToAppData
  , memberNameToString
  , stringToMemberName
  ) where

import StudyGroup.Types
  ( MemberName(..)
  , Interest(..)
  , StudySession(..)
  , AppData(..)
  )
import StudyGroup.Json.Types (JsonValue(..))

-- | MemberName ⇔ String 変換

memberNameToString :: MemberName -> String
memberNameToString Shiraoka = "shiraoka"
memberNameToString Nori     = "nori"

stringToMemberName :: String -> Maybe MemberName
stringToMemberName "shiraoka" = Just Shiraoka
stringToMemberName "nori"     = Just Nori
stringToMemberName _          = Nothing

-- | オブジェクトからフィールドを検索
lookupField :: String -> [(String, JsonValue)] -> Maybe JsonValue
lookupField _ []           = Nothing
lookupField key ((k,v):rest)
  | key == k  = Just v
  | otherwise = lookupField key rest

-- | Interest → JSON
interestToJson :: Interest -> JsonValue
interestToJson interest = JsonObject
  [ ("member", JsonString (memberNameToString (interestMember interest)))
  , ("topic",  JsonString (interestTopic interest))
  ]

-- | JSON → Interest
jsonToInterest :: JsonValue -> Maybe Interest
jsonToInterest (JsonObject fields) = do
  JsonString memberStr <- lookupField "member" fields
  member <- stringToMemberName memberStr
  JsonString topic <- lookupField "topic" fields
  Just (Interest member topic)
jsonToInterest _ = Nothing

-- | StudySession → JSON
sessionToJson :: StudySession -> JsonValue
sessionToJson session = JsonObject
  [ ("date",  JsonString (sessionDate session))
  , ("topic", JsonString (sessionTopic session))
  ]

-- | JSON → StudySession
jsonToSession :: JsonValue -> Maybe StudySession
jsonToSession (JsonObject fields) = do
  JsonString date  <- lookupField "date" fields
  JsonString topic <- lookupField "topic" fields
  Just (StudySession date topic)
jsonToSession _ = Nothing

-- | AppData → JSON
appDataToJson :: AppData -> JsonValue
appDataToJson appData = JsonObject
  [ ("interests", JsonArray (map interestToJson (appInterests appData)))
  , ("sessions",  JsonArray (map sessionToJson  (appSessions appData)))
  ]

-- | JSON → AppData
jsonToAppData :: JsonValue -> Maybe AppData
jsonToAppData (JsonObject fields) = do
  JsonArray interestValues <- lookupField "interests" fields
  interests <- mapMaybe jsonToInterest interestValues
  JsonArray sessionValues <- lookupField "sessions" fields
  sessions <- mapMaybe jsonToSession sessionValues
  Just (AppData interests sessions)
  where
    mapMaybe :: (a -> Maybe b) -> [a] -> Maybe [b]
    mapMaybe _ []     = Just []
    mapMaybe f (x:xs) = case f x of
      Nothing -> Nothing
      Just y  -> case mapMaybe f xs of
        Nothing -> Nothing
        Just ys -> Just (y : ys)
jsonToAppData _ = Nothing

