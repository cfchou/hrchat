# hrchat

A chat client and server in Haskell using RabbitMq.


![screenshot](https://github.com/cfchou/hrchat/raw/master/hrchat.png)

## Install

### Server

In addition to the latest Haskell Platform, you need to install package amqp:

```
cabal install amqp
```

```
ghc -o HRServer HRServer.hs
```

Obviously you also need to install RabbitMq.


### Client

On top of the latest Haskell Platform, you will need to install packages vty-ui
and amqp . Specifically,

```
cabal install amqp
```

```
cabal install vty-ui
```

```
ghc -o HRChat HRChat.hs
```

## Configure

For RabbitMq, you will need to configure vhost, user name, user password and
setup a read-write permission for the user on the vhost. For example:

```
rabbitmqctl add_vhost /hrchat
```

```
rabbitmqctl add_user hrchat chatty
```

```
rabbitmqctl set_permissions -p /hrchat hrchat ".*" ".*" ".*"
```

Then update ```hrchat.conf``` accordingly. For example:

```
hostname = YOUR_SERVER_IP
```

```
vhost = /hrchat
```

```
user = hrchat
```

```
password = chatty
```

## Run

#### Server

```
./HRServer hrchat.conf
```

Ctrl-C to quit

#### Client

```
./HRChat hrchat.conf
```

Press ESC to quit.

## License
MIT
