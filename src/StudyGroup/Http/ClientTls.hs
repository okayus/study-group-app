{-# LANGUAGE OverloadedStrings #-}

module StudyGroup.Http.ClientTls
  ( sendRequest
  ) where

import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import Data.Bits ((.&.), shiftL)
import Data.Word (Word8)
import qualified Network.HTTP.Client as HC
import Network.HTTP.Client (RequestBody(RequestBodyBS))
import Network.HTTP.Client.TLS (tlsManagerSettings)

import StudyGroup.Http.Types (HttpMethod(..), HttpRequest(..))

-- | http-client + http-client-tls ベースで HTTP/HTTPS リクエストを送信する。
-- 学習成果として残してある自作 StudyGroup.Http.Client は HTTP 専用かつ TCP 直叩きで、
-- Cloud Run のような HTTPS エンドポイントに繋がらない。
-- このモジュールはライブラリに委譲することで HTTPS 対応と URL 解析を任せる。
--
-- 第一引数の baseUrl は "http://localhost:8080" や "https://xxx.run.app" のような
-- スキーム付き URL。`parseRequest` がスキーム / ホスト / ポートを自動で解決するため、
-- CLI 側は環境変数の値をそのまま渡せばよい。
sendRequest :: String -> HttpRequest -> IO String
sendRequest baseUrl req = do
  -- TLS 対応 manager を作る。HTTP / HTTPS どちらのリクエストでも使える。
  manager <- HC.newManager tlsManagerSettings
  -- baseUrl + path を parseRequest に渡し、Request の雛形を得る。
  -- parseRequest は不正な URL に対して例外を投げる（IO に閉じている）。
  initial <- HC.parseRequest (baseUrl ++ requestPath req)
  -- 送信ボディも UTF-8 エンコードする。Char8.pack は各 Char の下位 8bit を
  -- そのままバイトにしてしまうので、日本語トピック等が破損する。
  let bodyBs = B.pack (encodeUtf8Chars (requestBody req))
      hcReq = initial
        { HC.method = B.pack (encodeUtf8Chars (showMethod (requestMethod req)))
        , HC.requestBody = RequestBodyBS bodyBs
        , HC.requestHeaders =
            if B.null bodyBs
              then HC.requestHeaders initial
              else ("Content-Type", "application/json") : HC.requestHeaders initial
        }
  response <- HC.httpLbs hcReq manager
  -- レスポンスボディは UTF-8 バイト列。Char8.unpack は Latin-1 として
  -- 各バイトを Char にしてしまうため、日本語が文字化けする。
  -- base のみで UTF-8 をデコードして [Char] に直す。
  return (decodeUtf8Bytes (B.unpack (BL.toStrict (HC.responseBody response))))

-- | Unicode 文字列を UTF-8 バイト列にエンコードする。
-- 自作 Cli.hs の toUtf8Bytes と同じロジックを Word8 ベースで実装する。
encodeUtf8Chars :: String -> [Word8]
encodeUtf8Chars = concatMap encodeChar
  where
    encodeChar c =
      let cp = fromEnum c
      in if cp <= 0x7F
           then [fromIntegral cp]
           else if cp <= 0x7FF
             then [ fromIntegral (0xC0 + cp `div` 64)
                  , fromIntegral (0x80 + cp `mod` 64)
                  ]
             else if cp <= 0xFFFF
               then [ fromIntegral (0xE0 + cp `div` 4096)
                    , fromIntegral (0x80 + (cp `div` 64) `mod` 64)
                    , fromIntegral (0x80 + cp `mod` 64)
                    ]
               else [ fromIntegral (0xF0 + cp `div` 262144)
                    , fromIntegral (0x80 + (cp `div` 4096) `mod` 64)
                    , fromIntegral (0x80 + (cp `div` 64) `mod` 64)
                    , fromIntegral (0x80 + cp `mod` 64)
                    ]

-- | UTF-8 バイト列を Unicode 文字列にデコードする。
-- 自作 Cli.hs の toUtf8Bytes と対になる関数。
-- RFC 3629 の先頭バイトパターンで継続バイト数を判定する:
--   0xxxxxxx → 1バイト (ASCII)
--   110xxxxx → 2バイト
--   1110xxxx → 3バイト (日本語はここ)
--   11110xxx → 4バイト
-- 不正なバイトは置換せずスキップする（学習用なので簡素な実装）。
decodeUtf8Bytes :: [Word8] -> String
decodeUtf8Bytes [] = []
decodeUtf8Bytes (b0:rest)
  | b0 < 0x80 =
      toEnum (fromIntegral b0) : decodeUtf8Bytes rest
  | b0 < 0xC0 =
      decodeUtf8Bytes rest  -- 単独で出現した継続バイトはスキップ
  | b0 < 0xE0 =
      case rest of
        (b1:xs) ->
          let cp = ((fromIntegral b0 .&. 0x1F) `shiftL` 6)
                 + (fromIntegral b1 .&. 0x3F)
          in toEnum cp : decodeUtf8Bytes xs
        _ -> []
  | b0 < 0xF0 =
      case rest of
        (b1:b2:xs) ->
          let cp = ((fromIntegral b0 .&. 0x0F) `shiftL` 12)
                 + ((fromIntegral b1 .&. 0x3F) `shiftL` 6)
                 + (fromIntegral b2 .&. 0x3F)
          in toEnum cp : decodeUtf8Bytes xs
        _ -> []
  | otherwise =
      case rest of
        (b1:b2:b3:xs) ->
          let cp = ((fromIntegral b0 .&. 0x07) `shiftL` 18)
                 + ((fromIntegral b1 .&. 0x3F) `shiftL` 12)
                 + ((fromIntegral b2 .&. 0x3F) `shiftL` 6)
                 + (fromIntegral b3 .&. 0x3F)
          in toEnum cp : decodeUtf8Bytes xs
        _ -> []

-- | HttpMethod を HTTP メソッド文字列に変換する。
-- 自作 Http.Client と同じく、show ではなく明示マッピングを使う。
-- show の表記が将来変わってもプロトコル送出値が壊れないようにするため。
showMethod :: HttpMethod -> String
showMethod GET     = "GET"
showMethod POST    = "POST"
showMethod DELETE  = "DELETE"
showMethod OPTIONS = "OPTIONS"
