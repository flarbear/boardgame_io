# boardgame_io

A Dart package to enable communication with a boardgame.io back end game server.
The boardgame.io project is implemented entirely in Node.js and comes with support
for Node.js front ends written in Javascript, TypeScript or React.

This package provides similar Dart language Client and Lobby classes to enable
a Dart (or Flutter) program to connect to a boardgame.io server and provide the
application front end half of the game in Dart or Flutter.

## Getting Started

A sample boardgame.io game based on the Tic-Tac-Toe tutorial and how to write the
front end in Dart can be found in the [example](example/) folder.

## Work in Progress

This package is currently a work in progress and only supports the functionality
used by the Tic-Tac-Toe example so far. Limitations include:

- No access to game events (which are usually not executed on the client side
anyway)
- All game moves must be executed on the server (using the `client: false` flag
on the long-form move.
- No support for phases or stages yet.
- No support for lobby rejoining of games yet.
- No support for local games that do not involve a server.
