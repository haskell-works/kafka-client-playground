{-# LANGUAGE TupleSections #-}
module Conduit
( kafkaSource
) where

import Control.Monad.IO.Class
import Control.Monad (void)
import Control.Arrow
import Data.Conduit
import Kafka
import Kafka.Consumer
import Control.Monad.Trans.Resource

kafkaSource :: (MonadResource m, MonadIO m)
                => KafkaConf                            -- ^ Consumer config (see 'newConsumerConf')
                -> TopicConf                            -- ^ Topic config that is going to be used for every topic consumed by the consumer
                -> BrokersString                        -- ^ Comma separated list of brokers with ports (e.g. @localhost:9092@)
                -> [TopicName]                          -- ^ List of topics to be consumed
                -> Timeout
                -> Source m (Either KafkaError ReceivedMessage)
kafkaSource kc tc bs ts t =
    bracketP mkConsumer clConsumer runHandler
    where
        mkConsumer = do
            setDefaultTopicConf kc tc
            kafka <- newConsumer bs kc
            left (, kafka) <$> subscribe kafka ts

        clConsumer (Left (_, kafka)) = void $ closeConsumer kafka
        clConsumer (Right kafka) = void $ closeConsumer kafka

        runHandler (Left (err, _)) = return ()
        runHandler (Right kafka) = do
          liftIO $ print "Let's poll"
          msg <- liftIO $ pollMessage kafka t
          yield msg
          runHandler (Right kafka)
