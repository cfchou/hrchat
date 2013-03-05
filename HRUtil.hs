
module HRUtil ( get_cconf, connect, Fanout(..), declare_fanout, Direct(..)
              , declare_ctrl_client, declare_ctrl_server
              , bkey_client, bkey_server) where

import Text.ParserCombinators.Parsec
import qualified Data.Map as M
import Network.AMQP
import Debug.Trace


-- parse the config file
get_cconf :: String -> M.Map String String
get_cconf s =
    case parse cconf "get_cconf" s of
         Left e -> trace ("Error: " ++ show e) $ M.empty
         Right lst -> foldl addm M.empty lst
    where addm m ss 
              | 2 <= length ss = M.insert (ss !! 0) (ss !! 1) m
              | otherwise = m
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

---------------------------------
xcg_chat = "room101" -- for fanout exchange

xcg_ctrl = "ctrl"    -- for direct exchange
bkey_client = "for_client"
bkey_server = "for_server"

 

data Fanout = Fanout { fconn :: Connection
                     , fchan :: Channel
                     , fqopts :: QueueOpts
                     , fxopts :: ExchangeOpts
                     }

connect :: M.Map String String -> IO (Connection, Channel)
connect m =
    case validation of
        Nothing -> fail "Error: hostname/vhost/user/password?"
        Just (h, v, u, p) -> openConnection h v u p >>= \conn ->
                             openChannel conn >>= \chan ->
                             return (conn, chan)
    where validation = M.lookup "hostname" m >>= \hostname ->  
                       M.lookup "vhost" m >>= \vhost ->
                       M.lookup "user" m >>= \user ->
                       M.lookup "password" m >>= \password ->
                       return (hostname, vhost, user, password)

declare_fanout :: Connection -> Channel -> IO Fanout
declare_fanout conn chan =
    let qo = newQueue { queueExclusive = True }
        xo = newExchange { exchangeName = xcg_chat
                         , exchangeType = "fanout" }
    in  declareQueue chan qo >>= \(qname, _, _) ->
        declareExchange chan xo >>
        bindQueue chan qname xcg_chat "" >> -- fanout ignores binding key
        return (Fanout conn chan (qo { queueName = qname }) xo)


data Direct = Direct { dconn :: Connection
                     , dchan :: Channel
                     , dqopts :: QueueOpts
                     , dxopts :: ExchangeOpts
                     , bkey :: String
                     }

declare_ctrl :: String -> Connection -> Channel -> IO Direct
declare_ctrl bkey conn chan =
    let qo = newQueue { queueExclusive = True }
        xo = newExchange { exchangeName = xcg_ctrl
                         , exchangeType = "direct" }
    in  declareQueue chan qo >>= \(qname, _, _) ->
        declareExchange chan xo >>
        bindQueue chan qname xcg_ctrl bkey >>
        return (Direct conn chan (qo { queueName = qname }) xo bkey)

declare_ctrl_client :: Connection -> Channel -> IO Direct
declare_ctrl_client = declare_ctrl bkey_client

declare_ctrl_server :: Connection -> Channel -> IO Direct
declare_ctrl_server = declare_ctrl bkey_server



