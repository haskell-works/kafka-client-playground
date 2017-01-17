{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
module Main where

import Control.Monad.IO.Class
import Control.Monad.Trans.Except
import Control.Error.Util
import Data.Avro
import qualified Data.Avro.Types as AT
import Data.Int
import Data.Text (Text)
import Kafka
import Kafka.Avro.SchemaRegistry
import Kafka.Avro.Decode
import Data.ByteString.Lazy (fromStrict, ByteString)
import Kafka.Conduit.Consumer
import Conduit
import Data.Conduit (Source, runConduit, runConduitRes, (.|))
import qualified Data.Conduit.List as L
import Control.Monad.Trans.Resource

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
main = do
  first5 <- runConduitRes $ creareKafkaStream .| L.take 5
  print first5

creareKafkaStream :: MonadResource m => Source m (Either KafkaError ReceivedMessage)
creareKafkaStream = do
  kc  <- newConsumerConf (ConsumerGroupId "test_group") emptyKafkaProps
  tc  <- newConsumerTopicConf (TopicProps [("auto.offset.reset", "earliest")])
  kafkaSource kc tc (BrokersString "localhost:9092") (Timeout 30000) [TopicName "dc_attacks"]

decodeMessage :: MonadIO m => SchemaRegistry -> ByteString -> ExceptT AppError m DedupInfo
decodeMessage sr bs =
  withExceptT DE $ decodeWithSchema sr bs
