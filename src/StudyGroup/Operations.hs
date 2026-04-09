module StudyGroup.Operations
  ( listInterests
  , addInterest
  , removeInterest
  , listSessions
  , addSession
  , listMembers
  ) where

import StudyGroup.Types
  ( MemberName(..)
  , Interest(..)
  , StudySession(..)
  , AppData(..)
  )

-- | 全メンバーを返す
listMembers :: AppData -> [MemberName]
listMembers _ = [Shiraoka, Nori]

-- | 特定メンバーの興味リストを返す
listInterests :: MemberName -> AppData -> [Interest]
listInterests member appData =
  filter (\i -> interestMember i == member) (appInterests appData)

-- | 興味を追加（重複チェック付き）
addInterest :: MemberName -> String -> AppData -> AppData
addInterest member topic appData =
  let existing = appInterests appData
      alreadyExists = any (\i -> interestMember i == member && interestTopic i == topic) existing
  in if alreadyExists
     then appData
     else appData { appInterests = Interest member topic : existing }

-- | 興味を削除
removeInterest :: MemberName -> String -> AppData -> AppData
removeInterest member topic appData =
  appData { appInterests = filter (not . matches) (appInterests appData) }
  where
    matches i = interestMember i == member && interestTopic i == topic

-- | 勉強会予定一覧
listSessions :: AppData -> [StudySession]
listSessions = appSessions

-- | 勉強会予定を追加
addSession :: String -> String -> AppData -> AppData
addSession date topic appData =
  appData { appSessions = StudySession date topic : appSessions appData }
