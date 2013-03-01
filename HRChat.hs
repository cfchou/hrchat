-- HRChat.hs
-- Haskell-RabbitMq-Chat client
--
-- http://hackage.haskell.org/packages/archive/amqp/0.3.3/doc/html/Network-AMQP.html
-- http://videlalvaro.github.com/2010/09/haskell-and-rabbitmq.html

import System.IO
import System.Environment
import Control.Monad
import Text.ParserCombinators.Parsec
import qualified Data.Map as M
import Network.AMQP

data CConf = CConf { hostname :: String
                   , virtualHost :: String
                   , login :: String
                   , password :: String
                   } deriving (Show)

cconf = many row

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


path = "test.conf"

main = readFile path >>= \c ->
       case parse cconf "fail" c of
            Left e -> putStr ("Error: " ++ path) >>
                      print e
            Right result -> mapM_ print result



