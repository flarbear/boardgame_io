# tic_tac_toe

A sample project demonstrating the mixing of boardgame.io NodeJs backend with the
dart front end.

## Getting Started

You will need to execute the following commands to get this project up and running.

First, for the server side, initializing the support for the boardgame.io server:

npm init
npm install boardgame.io
npm install esm

Then you run the server with the following command:

npm run-script serve

Optionally, if you want to verify that the server is working properly, the following
commands will allow you to start up the boardgame.io front end written in NodeJs:

npm install --save-dev parcel-bundler
npm start

Moving on to the dart front end that shows how to use this package to communicate
with the boardgame.io server:

pub get
dart lib/main.dart
