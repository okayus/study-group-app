module StudyGroup.Cli
  ( Command(..)
  , parseArgs
  , executeCommand
  ) where

import StudyGroup.Http.Types (HttpMethod(..), HttpRequest(..))
import StudyGroup.Http.Client (sendRequest)
import StudyGroup.Json.Types (JsonValue(..))
import StudyGroup.Json.Parser (parseJson)
import StudyGroup.Json.Printer (renderJson)

-- | CLI コマンドの代数的データ型。
-- ユーザーが指定できる全操作を網羅する Sum Type。
-- パターンマッチで全コマンドを漏れなく処理でき、
-- 新しいコマンドを追加すると未処理箇所がコンパイル警告になる。
data Command
  = InterestsList (Maybe String)   -- interests list [NAME]
  | InterestsAdd String String     -- interests add NAME TOPIC
  | InterestsRemove String String  -- interests remove NAME TOPIC
  | SessionsList                   -- sessions list
  | SessionsAdd String String      -- sessions add DATE TOPIC
  deriving (Show, Eq)

-- | コマンドライン引数をパターンマッチで Command に変換する。
-- getArgs の結果（文字列リスト）を受け取り、
-- 認識できるパターンなら Just Command、できなければ Nothing を返す。
-- Maybe を使うことで不正な引数を型安全に扱える。
parseArgs :: [String] -> Maybe Command
parseArgs ["interests", "list"]            = Just (InterestsList Nothing)
parseArgs ["interests", "list", name]      = Just (InterestsList (Just name))
parseArgs ["interests", "add", name, topic] = Just (InterestsAdd name topic)
parseArgs ["interests", "remove", name, topic] = Just (InterestsRemove name topic)
parseArgs ["sessions", "list"]             = Just SessionsList
parseArgs ["sessions", "add", date, topic] = Just (SessionsAdd date topic)
parseArgs _                                = Nothing

-- | API サーバーのホスト名とポート番号。
-- ローカル開発では localhost:8080 固定。
-- 将来的に環境変数や引数で切り替える場合はここを変更する。
apiHost :: String
apiHost = "localhost"

apiPort :: Int
apiPort = 8080

-- | Command を実行する。
-- 各コマンドを対応する HTTP リクエストに変換し、
-- API サーバーに送信して結果を表示する。
-- 純粋な変換（Command → HttpRequest）と IO（送信・表示）を分離し、
-- パターンマッチで全コマンドを網羅的に処理する。
executeCommand :: Command -> IO ()
executeCommand (InterestsList Nothing) = do
  body <- sendRequest apiHost apiPort (mkRequest GET "/members" "")
  case parseJson body of
    Just (JsonArray members) ->
      mapM_ (putStrLn . formatMember) members
    _ -> putStrLn body

executeCommand (InterestsList (Just name)) = do
  body <- sendRequest apiHost apiPort
    (mkRequest GET ("/members/" ++ name ++ "/interests") "")
  case parseJson body of
    Just (JsonArray interests) ->
      mapM_ (putStrLn . formatInterest) interests
    _ -> putStrLn body

executeCommand (InterestsAdd name topic) = do
  let jsonBody = renderJson (JsonObject [("topic", JsonString topic)])
  body <- sendRequest apiHost apiPort
    (mkRequest POST ("/members/" ++ name ++ "/interests") jsonBody)
  case parseJson body of
    Just val -> putStrLn ("Added: " ++ formatInterest val)
    _        -> putStrLn body

executeCommand (InterestsRemove name topic) = do
  let encodedTopic = encodeURIComponent topic
  _ <- sendRequest apiHost apiPort
    (mkRequest DELETE ("/members/" ++ name ++ "/interests/" ++ encodedTopic) "")
  putStrLn ("Removed: " ++ topic ++ " from " ++ name)

executeCommand SessionsList = do
  body <- sendRequest apiHost apiPort (mkRequest GET "/sessions" "")
  case parseJson body of
    Just (JsonArray sessions) ->
      mapM_ (putStrLn . formatSession) sessions
    _ -> putStrLn body

executeCommand (SessionsAdd date topic) = do
  let jsonBody = renderJson (JsonObject
        [ ("date", JsonString date)
        , ("topic", JsonString topic)
        ])
  body <- sendRequest apiHost apiPort
    (mkRequest POST "/sessions" jsonBody)
  case parseJson body of
    Just val -> putStrLn ("Added: " ++ formatSession val)
    _        -> putStrLn body

-- | HTTP リクエストを組み立てるヘルパー。
-- CLI の各コマンドはメソッド・パス・ボディだけが異なるため、
-- 共通部分をまとめて冗長さを排除する。
-- ヘッダーは sendRequest 側で Host 等を自動付与するため空リスト。
mkRequest :: HttpMethod -> String -> String -> HttpRequest
mkRequest method path body = HttpRequest
  { requestMethod  = method
  , requestPath    = path
  , requestHeaders = []
  , requestBody    = body
  }

-- | JSON のメンバー名を人間が読みやすい表示名に変換する。
-- API が返す "shiraoka" / "nori" を日本語名に変換して表示する。
-- 未知のメンバー名はそのまま返す。
displayName :: String -> String
displayName "shiraoka" = "しらおかさん"
displayName "nori"     = "ノリさん"
displayName name       = name

-- | JSON メンバー値を表示用文字列に変換する。
-- API の GET /members が返す JsonString をパターンマッチで処理。
formatMember :: JsonValue -> String
formatMember (JsonString name) = displayName name
formatMember val = show val

-- | JSON 興味オブジェクトを表示用文字列に変換する。
-- {"member":"nori","topic":"Rust"} → "ノリさん: Rust"
-- フィールドが不足している場合は JSON をそのまま表示する。
formatInterest :: JsonValue -> String
formatInterest (JsonObject fields) =
  case (lookup "member" fields, lookup "topic" fields) of
    (Just (JsonString member), Just (JsonString topic)) ->
      displayName member ++ ": " ++ topic
    _ -> renderJson (JsonObject fields)
formatInterest val = renderJson val

-- | JSON セッションオブジェクトを表示用文字列に変換する。
-- {"date":"2026-04-16","topic":"HTTP server"} → "2026-04-16  HTTP server"
-- 日付とトピックを2スペースで区切って表示する。
formatSession :: JsonValue -> String
formatSession (JsonObject fields) =
  case (lookup "date" fields, lookup "topic" fields) of
    (Just (JsonString date), Just (JsonString topic)) ->
      date ++ "  " ++ topic
    _ -> renderJson (JsonObject fields)
formatSession val = renderJson val

-- | 文字列を URL パーセントエンコードする。
-- DELETE リクエストで日本語トピック名をパスに含める際に使う。
-- API サーバー側の decodeURIComponent と対になる関数。
-- ASCII 英数字とハイフン・アンダースコア・ピリオド・チルダはそのまま、
-- それ以外は %XX 形式に変換する。
-- 日本語は Haskell の Char が Unicode コードポイントなので、
-- 各コードポイントの UTF-8 バイト列に変換してからエンコードする。
encodeURIComponent :: String -> String
encodeURIComponent = concatMap encodeChar
  where
    encodeChar c
      | isUnreserved c = [c]
      | otherwise      = concatMap encodeByte (toUtf8Bytes (fromEnum c))

    isUnreserved c =
      (c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      (c >= '0' && c <= '9') ||
      c == '-' || c == '_' || c == '.' || c == '~'

    encodeByte b = '%' : toHexDigit (b `div` 16) : toHexDigit (b `mod` 16) : []

    toHexDigit n
      | n < 10    = toEnum (fromEnum '0' + n)
      | otherwise = toEnum (fromEnum 'A' + n - 10)

-- | Unicode コードポイントを UTF-8 バイト列に変換する。
-- RFC 3629 に準拠した変換ロジック:
--   U+0000..U+007F   → 1バイト
--   U+0080..U+07FF   → 2バイト
--   U+0800..U+FFFF   → 3バイト (日本語はこの範囲)
--   U+10000..U+10FFFF → 4バイト
toUtf8Bytes :: Int -> [Int]
toUtf8Bytes cp
  | cp <= 0x7F   = [cp]
  | cp <= 0x7FF  = [ 0xC0 + cp `div` 64
                   , 0x80 + cp `mod` 64
                   ]
  | cp <= 0xFFFF = [ 0xE0 + cp `div` 4096
                   , 0x80 + (cp `div` 64) `mod` 64
                   , 0x80 + cp `mod` 64
                   ]
  | otherwise    = [ 0xF0 + cp `div` 262144
                   , 0x80 + (cp `div` 4096) `mod` 64
                   , 0x80 + (cp `div` 64) `mod` 64
                   , 0x80 + cp `mod` 64
                   ]
