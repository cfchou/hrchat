
module HRUtil (get_cconf, Fanout(..), declare_fanout) where

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
xcg_chat = "room101"
 

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


