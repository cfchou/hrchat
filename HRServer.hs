
import System.IO
import System.Environment
import System.Posix.Signals
import System.Posix.Process
import System.Posix.IO
import System.Exit
import Control.Concurrent.Chan
import qualified Data.List as L
import qualified Data.Set as S
import qualified Data.ByteString.Lazy.Char8 as BL
import Network.AMQP
import HRUtil

-- pidfile = "/var/run/hrchat.pid"

main =
    getArgs >>= \args ->
    if length args < 1 then
        putStrLn "Please give config file name."
    else 
        -- daemonize >>
        -- (writeFile pidfile . show =<< getProcessID) >>
        putStrLn "Server starts ......" >>
        readFile (head args) >>= \c ->
        connect (get_cconf c) >>= \conn ->

        installHandler sigTERM (Catch $ sigterm_handler "sigTERM" conn) 
            Nothing >>
        installHandler sigQUIT (Catch $ sigterm_handler "sigQUIT" conn) 
            Nothing >>
        installHandler sigINT (Catch $ sigterm_handler "sigINT" conn) 
            Nothing >>

        openChannel conn >>= \chan ->
        declare_ctrl_server conn chan >>= \drct ->
        newChan >>= \fifo ->
        consumeMsgs chan (queueName $ dqopts drct) Ack (consume_msg fifo) >>
        produce_msg S.empty fifo drct

{--
daemonize :: IO ()
daemonize = forkProcess child1 >>
                  exitImmediately ExitSuccess
    where child1 = createSession >>
                  forkProcess child2 >>
                  exitImmediately ExitSuccess
          child2 = mapM_ closeFd [stdInput, stdOutput, stdError] >>
                   openFd "/dev/null" ReadWrite Nothing 
                       defaultFileFlags >>= \nullfd ->
                   mapM_ (dupTo nullfd) [stdInput, stdOutput, stdError] >>
                   closeFd nullfd
--}

sigterm_handler :: String -> Connection -> IO ()
sigterm_handler reason conn =
    (putStrLn $ "Server exits because " ++ reason) >>
    closeConnection conn >>
    raiseSignal sigKILL


-- Read FIFO, update the users list which is then converted to the format
-- "user1:user2:user3" and finally published to client.
produce_msg :: S.Set String -> Chan String -> Direct -> IO ()
produce_msg users fifo drct =
    readChan fifo >>= \str ->
    let users' = case head str of
                     '+' -> S.insert (tail str) users
                     '-' -> S.delete (tail str) users
                     _ -> users
        s = L.intercalate ":" (S.toList users')
    in  publishMsg (dchan drct) (exchangeName $ dxopts drct) bkey_client
            newMsg { msgBody = BL.pack s
                   , msgDeliveryMode = Just NonPersistent } >>
    produce_msg users' fifo drct


-- Consume client logon/logoff messges in the format of ":+user" or ":-user".
-- Write FIFO the string without the leading ':'.
consume_msg :: Chan String -> (Message, Envelope) -> IO ()
consume_msg fifo (m, e) = 
    let s = BL.unpack $ msgBody m
    in  ackEnv e >>
        if length s > 2 && head s == ':' && (s !! 1) `elem` "+-" then
            writeChan fifo (tail s)
        else
            return ()




