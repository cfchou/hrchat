-- HRChat.hs
-- Haskell-RabbitMq-Chat client
--
-- http://hackage.haskell.org/packages/archive/amqp/0.3.3/doc/html/Network-AMQP.html
-- http://videlalvaro.github.com/2010/09/haskell-and-rabbitmq.html
-- http://www.haskell.org/haskellwiki/Implement_a_chat_server

import System.IO
import System.Environment
import Control.Monad
import Text.ParserCombinators.Parsec
import qualified Data.Map as M
import Network.AMQP
import Debug.Trace

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

get_cconf :: String -> M.Map String String
get_cconf s =
    case parse cconf "get_cconf" s of
         Left e -> trace ("Error: " ++ show e) $ M.empty
         Right lst -> foldl addm M.empty lst
    where addm m ss 
              | 2 <= length ss = M.insert (ss !! 0) (ss !! 1) m
              | otherwise = m
 
connect :: M.Map String String -> IO Connection
connect m = case validation of
                 Nothing -> fail "Error: hostname/vhost/user/password?"
                 Just (h, v, u, p) -> openConnection h v u p
    where validation = M.lookup "hostname" m >>= \hostname ->  
                       M.lookup "vhost" m >>= \vhost ->
                       M.lookup "user" m >>= \user ->
                       M.lookup "password" m >>= \password ->
                       return (hostname, vhost, user, password)

main = readFile conf_name >>= \c ->
       let m = get_cconf c
       in  connect m >>= \conn ->
           closeConnection conn



