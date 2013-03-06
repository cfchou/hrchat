
import System.IO
import System.Posix.Signals
import Control.Concurrent.Chan
import qualified Data.List as L
import qualified Data.Set as S
import qualified Data.ByteString.Lazy.Char8 as BL
import Network.AMQP
import HRUtil

conf_name = "test.conf"

main =
    readFile conf_name >>= \c ->
    connect (get_cconf c) >>= \conn ->
    openChannel conn >>= \chan ->
    declare_ctrl_server conn chan >>= \drct ->
    newChan >>= \fifo ->
    consumeMsgs chan (queueName $ dqopts drct) Ack (consume_msg fifo) >>
    produce_msg S.empty fifo drct

produce_msg :: S.Set String -> Chan String -> Direct -> IO ()
produce_msg users fifo drct =
    readChan fifo >>= \str ->
    let users' = case head str of
                     '+' -> S.insert (tail str) users
                     '-' -> S.delete (tail str) users
                     _ -> users
        s = L.intercalate ":" (S.toAscList users')
    in  publishMsg (dchan drct) (exchangeName $ dxopts drct) bkey_client
            newMsg { msgBody = BL.pack s
                   , msgDeliveryMode = Just NonPersistent } >>
    produce_msg users' fifo drct


consume_msg :: Chan String -> (Message, Envelope) -> IO ()
consume_msg fifo (m, e) = 
    let s = BL.unpack $ msgBody m
    in  if length s > 2 && head s == ':' && (s !! 1) `elem` "+-" then
            writeChan fifo (tail s) >>
            ackEnv e
        else
            ackEnv e





