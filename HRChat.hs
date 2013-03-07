-- HRChat.hs
-- Haskell-RabbitMq-Chat client
--
-- http://hackage.haskell.org/packages/archive/amqp/0.3.3/doc/html/Network-AMQP.html
-- http://videlalvaro.github.com/2010/09/haskell-and-rabbitmq.html
-- http://www.haskell.org/haskellwiki/Implement_a_chat_server

import System.IO
import System.Exit ( exitSuccess )
import System.Environment
import Control.Monad
import qualified Data.Map as M
import qualified Data.ByteString.Lazy.Char8 as BL
import Network.AMQP
import Graphics.Vty ( Key(..) )
import Graphics.Vty.Attributes
import Graphics.Vty.Widgets.All
import qualified Data.Text as T
import HRUtil
import Debug.Trace

conf_name = "hrchat.conf"

data MainUI = MainUI { edit :: Widget Edit
                     , conv :: Widget (List String FormattedText)
                     , lst :: Widget (List String FormattedText)
                     , fg :: Widget FocusGroup
                     , col :: Collection
                     }

-- standard 80 * 40 terminal should be fine
hmax_lst = 27 -- terminal should be more than 3 times wider than this
hmax_name = hmax_lst - 2
vmax_app = 30 -- terminal should be at least this height

compose_ui :: IO MainUI
compose_ui =
    editWidget >>= \edit ->
    newList def_attr >>= \conv ->
    newList def_attr >>= \lst ->

    (vBox lst =<< plainText (T.pack "ESC to quit")) >>= \right ->
    (bordered =<< vLimit vmax_app =<< 
        vBox conv edit <++> vBorder <++> hLimit hmax_lst right) 
        >>= \app ->

    newFocusGroup >>= \fg ->
    addToFocusGroup fg edit >>
    newCollection >>= \col ->
    addToCollection col app fg >>
    return (MainUI edit conv lst fg col)


main =
    putStrLn ("User name? (No more than " ++ show hmax_name ++
        " chars; ':' is invalid)") >>
    take hmax_name `fmap` getLine >>= \me ->
    if any (== ':') me || null me then exitSuccess
    else readFile conf_name >>= \c ->
         connect (get_cconf c) >>= \conn ->
         -- for chat
         openChannel conn >>= \chan ->
         declare_fanout conn chan >>= \fo ->
         -- for ctrl
         openChannel conn >>= \chan_ctl ->
         declare_ctrl_client conn chan_ctl >>= \drct ->

         compose_ui >>= \ui ->
         setup_edit_handler fo me (edit ui) >>
         setup_conv_handler (conv ui) >>
         setup_fg_handler drct me (fg ui) >>

         consumeMsgs chan (queueName $ fqopts fo) Ack 
             (consume_msg ui) >>
         consumeMsgs chan_ctl (queueName $ dqopts drct) Ack 
             (consume_msg_direct ui) >>

         logon_msg drct True me >>
         runUi (col ui) defaultContext

-- When Edit widget receives Enter:
-- Publish text in the widget.
setup_edit_handler :: Fanout -> String -> Widget Edit -> IO ()
setup_edit_handler fo me this =
    this `onActivate` produce_msg fo me >> return ()

-- When FocusGroup gets keyboard input:
-- Quit the applicatioin if it's ESC; Otherwise forward down to Edit Widget.
setup_fg_handler :: Direct -> String -> Widget FocusGroup -> IO ()
setup_fg_handler drct me this =
    this `onKeyPressed` (\_ k _ ->
        if k == KEsc then
            logon_msg drct False me >>
            closeConnection (dconn drct) >> exitSuccess
        else return False)

-- When Conversation list gets updated: 
-- Maintain visible region(scroll up) if neccesary.
setup_conv_handler :: Widget (List String FormattedText) -> IO ()
setup_conv_handler this =
    this `onItemAdded` \(NewItemEvent i _ _) ->
        if i >= vmax_app - 2 then 
            removeFromList this 0 >> return ()
        else return ()


-- Publish(fanout) chat messages in the format of "myname:msg".
produce_msg :: Fanout -> String -> Widget Edit -> IO ()
produce_msg fo me this =
    getEditText this >>= \txt ->
    let s = me ++ (':' : T.unpack txt)
    in  publishMsg (fchan fo) (exchangeName $ fxopts fo) ""
            newMsg { msgBody = BL.pack s
                   , msgDeliveryMode = Just NonPersistent } >>
        setEditText this (T.pack "")


-- Consume(fanout) chat messages in the format of "myname:msg".
-- Schedule for main thread to update UI for conversation list accordingly.
consume_msg :: MainUI -> (Message, Envelope) -> IO ()
consume_msg ui (m, e) = 
    let (name, _:msg) = span (/= ':') (BL.unpack $ msgBody m)
        s = name ++ ": " ++ msg
    in  ackEnv e >>
        schedule (addToList (conv ui) "" =<< plainText (T.pack s))


-- Publish logon/logoff msg to server in the format of ":+user" or ":-user"
logon_msg :: Direct -> Bool -> String -> IO ()
logon_msg drct onoff me =
    let s = ':' : (if onoff then '+' : me else '-' : me)
    in  publishMsg (dchan drct) (exchangeName $ dxopts drct) bkey_server
            newMsg { msgBody = BL.pack s
                   , msgDeliveryMode = Just NonPersistent }


-- Consume user list messges from server (format: "user1:user2:user3").
-- Schedule for main thread to update UI for user list accordingly.
consume_msg_direct :: MainUI -> (Message, Envelope) -> IO ()
consume_msg_direct ui (m, e) = 
    let str = BL.unpack $ msgBody m
        users s ss = if null s then ss  
                     else let (x, xs) = break (== ':') s 
                              s' = if length xs > 1 then tail xs else []
                          in  users s' (x : ss)
        lst' = lst ui
    in  --putStrLn s >>
        ackEnv e >>
        schedule (
            clearList lst' >>
            forM_ (users str []) (\u ->
                addToList lst' "" =<< plainText (T.pack u)))


