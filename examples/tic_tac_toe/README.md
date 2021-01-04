# tic_tac_toe

A sample project demonstrating the mixing of boardgame.io Node.js backend with the
dart front end.

## Getting Started

You will need to execute the following commands to get this project up and running.

First, for the server side, initializing the support for the boardgame.io server:

```sh
npm install boardgame.io
npm install esm
```

Then you run the server with the following command:

```sh
npm run-script serve
```

Optionally, if you want to verify that the server is working properly, the following
commands will allow you to start up the boardgame.io front end written in Node.js:

```sh
npm install --save-dev parcel-bundler
npm start
```

But the point of this package is to enable communicating with the boardgame.io server
from a Dart (and thus potentially Flutter) front end. To run the simple ascii-interface
Dart front end for the Tic-Tac-Toe server, use the following command:

Initial setup:

```sh
pub get
```

Running the front end:

```sh
dart lib/main.dart [--help | -?] [--name "Player name"] [--allow-spectators] [--debug]
```

```sh
% dart lib/main.dart -h
-h, --[no-]help                display this usage information
    --[no-]debug               Set logging level to ALL
    --[no-]allow-spectators    Include option to join any match as a spectator
    --name=<String>            Specify the name that this player will use
```

For tic-tac-toe you want at least 2 terminal windows open and run the following commands:

```sh
Tty-1% dart lib/main.dart [--name Player1]
[create a match]
```
```sh
Tty-2% dart lib/main.dart [--name Player2]
[join the empty seat from the match created in the first terminal]
```

and optionally, to test out the spectator feature:

```sh
Tty-3% dart lib/main.dart [--name Spectator] --allow-spectators
[join the spectator seat in the match created in the first terminal]
```
