-- HRChat.hs
-- Haskell-RabbitMq-Chat client
--
-- http://hackage.haskell.org/packages/archive/amqp/0.3.3/doc/html/Network-AMQP.html
-- http://videlalvaro.github.com/2010/09/haskell-and-rabbitmq.html
-- http://www.haskell.org/haskellwiki/Implement_a_chat_server

import System.IO
import System.Exit ( exitSuccess )
import System.Environment
--import Control.Concurrent
import Control.Monad
import Text.ParserCombinators.Parsec
import qualified Data.Map as M
import qualified Data.ByteString.Lazy.Char8 as BL
import Network.AMQP
import Debug.Trace
import Graphics.Vty ( Key(..) )
import Graphics.Vty.Attributes
import Graphics.Vty.Widgets.All
import qualified Data.Text as T

-- [[String]]
cconf = many row

-- [String]
row = record >>= \result->
      eol >>
      return result

record = field `sepBy` (char '=')

field = optional whitespace >>
        bare_string >>= \result->
        optional whitespace >>
        return result

eol = string "\n"
whitespace = many space_char
space_char = char ' ' <|> char '\t'
bare_string = many bare_char
bare_char = noneOf "\n= "


conf_name = "test.conf"
xcg_chat = "room101"

get_cconf :: String -> M.Map String String
get_cconf s =
    case parse cconf "get_cconf" s of
         Left e -> trace ("Error: " ++ show e) $ M.empty
         Right lst -> foldl addm M.empty lst
    where addm m ss 
              | 2 <= length ss = M.insert (ss !! 0) (ss !! 1) m
              | otherwise = m
 

data Fanout = Fanout { conn :: Connection
                     , chan :: Channel
                     , qopts :: QueueOpts
                     , xopts :: ExchangeOpts
                     }

declare_fanout :: M.Map String String -> IO Fanout
declare_fanout m =
    let qo = newQueue { queueExclusive = True }
        xo = newExchange { exchangeName = xcg_chat
                         , exchangeType = "fanout" }
    in  connect m >>= \conn ->
        openChannel conn >>= \chan ->
        declareQueue chan qo >>= \(qname, _, _) ->
        declareExchange chan xo >>
        bindQueue chan qname xcg_chat "" >> -- fanout ignores binding key
        return (Fanout conn chan (qo { queueName = qname }) xo)
    where connect m =
              case validation of
                  Nothing -> fail "Error: hostname/vhost/user/password?"
                  Just (h, v, u, p) -> openConnection h v u p
          validation = M.lookup "hostname" m >>= \hostname ->  
                       M.lookup "vhost" m >>= \vhost ->
                       M.lookup "user" m >>= \user ->
                       M.lookup "password" m >>= \password ->
                       return (hostname, vhost, user, password)

main =
    putStrLn "User name? (No more than 10 chars; ':' is invalid)" >>
    take 10 `fmap` getLine >>= \me ->
    if any (== ':') me || null me then exitSuccess
    else readFile conf_name >>= \c ->
         declare_fanout (get_cconf c) >>= \fo ->

         -- compose ui
         editWidget >>= \edit ->
         setup_edit_handler fo me edit >>
         newList def_attr >>= \lst ->
         setup_list_handler lst >>
         (vLimit 26 =<< centered =<< vLimit 25 =<< vBox lst edit) >>=
             bordered >>= \cen ->
         newFocusGroup >>= \fg ->
         setup_fg_handler (conn fo) fg >>
         addToFocusGroup fg edit >>
         newCollection >>= \col ->
         addToCollection col cen fg >>

         consumeMsgs (chan fo) (queueName $ qopts fo) Ack (consume_msg lst) >>
         runUi col defaultContext



setup_edit_handler :: Fanout -> String -> Widget Edit -> IO ()
setup_edit_handler fo me this =
    this `onActivate` produce_msg fo me >> return ()

setup_fg_handler :: Connection -> Widget FocusGroup -> IO ()
setup_fg_handler conn this =
    this `onKeyPressed` (\_ k _ ->
        if k == KEsc then closeConnection conn >> exitSuccess
        else return False)

setup_list_handler :: Widget (List String FormattedText) -> IO ()
setup_list_handler this =
    this `onItemAdded` \(NewItemEvent i _ _) ->
        if i >= 24 then 
            removeFromList this 0 >> return ()
        else return ()


produce_msg :: Fanout -> String -> Widget Edit -> IO ()
produce_msg fo me this =
    getEditText this >>= \txt ->
    let s = me ++ (':' : T.unpack txt)
    in  publishMsg (chan fo) (exchangeName $ xopts fo) ""
            newMsg { msgBody = BL.pack s
                   , msgDeliveryMode = Just NonPersistent } >>
        setEditText this (T.pack "")

consume_msg :: Widget (List String FormattedText) -> (Message, Envelope) 
               -> IO ()
consume_msg this (m, e) = 
    let (name, _:msg) = span (/= ':') (BL.unpack $ msgBody m)
        s = name ++ ": " ++ msg
    in  ackEnv e >>
        schedule (addToList this "" =<< plainText (T.pack s))




