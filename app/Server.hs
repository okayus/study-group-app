module Main where

import Data.IORef (newIORef)
import StudyGroup.Storage (loadData, dataFilePath)
import StudyGroup.Http.Server (runServer)
import StudyGroup.Api (handleRequest)

main :: IO ()
main = do
  putStrLn "Loading data..."
  appData <- loadData dataFilePath
  ref <- newIORef appData
  putStrLn "Starting study-group-server on port 8080"
  runServer 8080 (handleRequest ref)
