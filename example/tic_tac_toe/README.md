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
dart --no-sound-null-safety run lib/main.dart ["Player name"]
```
