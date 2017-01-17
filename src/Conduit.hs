{-# LANGUAGE TupleSections #-}
module Conduit where

import Control.Monad.IO.Class
import Control.Monad.Trans.Resource
import Data.Conduit
import Kafka
import Kafka.Producer (ProduceMessage(..), ProducePartition(..))
import qualified Kafka.Producer as K

newProducerConf :: MonadIO m => KafkaProps -> m KafkaConf
newProducerConf = liftIO . K.newProducerConf

newProducer :: MonadIO m => BrokersString -> KafkaConf -> m Kafka
newProducer bs kc = liftIO $ K.newProducer bs kc

drainOutQueue :: MonadIO m => Kafka -> m ()
drainOutQueue = liftIO . drainOutQueue

newKafkaTopic :: MonadIO m => Kafka -> String -> TopicProps -> m KafkaTopic
newKafkaTopic k t p = liftIO $ K.newKafkaTopic k t p

kafkaSink :: MonadResource m
          => BrokersString
          -> KafkaConf
          -> String
          -> TopicProps
          -> Sink ProduceMessage m ()
kafkaSink bs kc t p =
  bracketP mkProducer clProducer runHandler
  where
    mkProducer = do
      prod <- newProducer bs kc
      top  <- newKafkaTopic prod t p
      return (prod, top)

    clProducer (prod, top) = drainOutQueue prod

    runHandler (kafka, top) = do
      msg <- await
      case msg of
        Just val -> do
          liftIO $ K.produceMessage top UnassignedPartition val
          runHandler (kafka, top)
        Nothing  -> return ()
