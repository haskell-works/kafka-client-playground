{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Monad.IO.Class
import Control.Monad.Trans.Except
import Control.Error.Util
import Data.Avro
import qualified Data.Avro.Types as AT
import Data.Int
import Data.Text (Text)
import Kafka
import Kafka.Consumer
import Kafka.Avro.SchemaRegistry
import Kafka.Avro.Decode
import Data.ByteString.Lazy (fromStrict, ByteString)

data DedupInfo = DedupInfo Int64 Text Bool Int64 deriving (Show, Eq, Ord)

data AppError = KE KafkaError | DE DecodeError deriving (Show)

instance FromAvro DedupInfo where
  fromAvro (AT.Record _ r) =
    DedupInfo <$> r .: "id"
              <*> r .: "submitter_ip"
              <*> r .: "is_duplicate"
              <*> r .: "timestamp"
  fromAvro v = badValue v "DedupInfo"

main :: IO ()
main = runConsumerExample

runConsumerExample :: IO ()
runConsumerExample = do
  sr  <- schemaRegistry "http://localhost:8081"
  res <- runConsumer
           (ConsumerGroupId "test_group")    -- consumer group id is required
           (BrokersString "localhost:9092")  -- kafka brokers to connect to
           emptyKafkaProps                   -- extra kafka conf properties
           emptyTopicProps                   -- extra topic conf props (like offset reset, etc.)
           [TopicName "attacks-dedup-info"]  -- list of topics to consume, supporting regex
           (processMessages sr)              -- handler to consume messages
  print $ show res

processMessages :: SchemaRegistry -> Kafka -> IO (Either KafkaError ())
processMessages sr kafka = do
  mapM_ (\_ -> do
            res <- runExceptT $ do
                     msg1 <- withExceptT KE $ ExceptT $ liftIO $ pollMessage kafka (Timeout 1000)
                     dec  <- decodeMessage sr (fromStrict $ messagePayload msg1)
                     liftIO $ print dec
                     return ()
            print res
        ) [1..100]
  return $ Right ()

decodeMessage :: MonadIO m => SchemaRegistry -> ByteString -> ExceptT AppError m DedupInfo
decodeMessage sr bs =
  withExceptT DE $ decodeWithSchema sr bs

--liftExceptT :: MonadIO m => ExceptT l IO r -> ExceptT l m r
--liftExceptT = mapExceptT liftIO
