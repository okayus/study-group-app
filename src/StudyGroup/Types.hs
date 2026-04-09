module StudyGroup.Types
  ( MemberName(..)
  , Interest(..)
  , StudySession(..)
  , AppData(..)
  ) where

data MemberName = Shiraoka | Nori
  deriving (Show, Eq)

data Interest = Interest
  { interestMember :: MemberName
  , interestTopic  :: String
  } deriving (Show, Eq)

data StudySession = StudySession
  { sessionDate  :: String   -- "YYYY-MM-DD" 形式
  , sessionTopic :: String
  } deriving (Show, Eq)

data AppData = AppData
  { appInterests :: [Interest]
  , appSessions  :: [StudySession]
  } deriving (Show, Eq)
