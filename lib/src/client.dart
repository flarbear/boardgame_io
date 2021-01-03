/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

import 'dart:convert';

import 'package:socket_io_client/socket_io_client.dart' as IO;

import './game.dart';
import './lobby.dart';

List<String> _toStringList(List<dynamic> rawList) => rawList.map<String>((e) => e.toString()).toList();

class ClientContext {
  ClientContext._fromJson(Map<String,dynamic> jsonData)
      : this.numPlayers = jsonData['numPlayers'],
        this.turn = jsonData['turn'],
        this.currentPlayer = jsonData['currentPlayer'],
        this.playerOrder = _toStringList(jsonData['playOrder']),
        this.playOrderPos = jsonData['playOrderPos'],
        this.phase = jsonData['phase'],
        this.gameOver = jsonData['gameover']
  {
    // print('ctx: '+JsonEncoder.withIndent('  ').convert(jsonData));
  }

  final int numPlayers;
  final int turn;
  final String currentPlayer;
  final List<String> playerOrder;
  final int playOrderPos;
  final String? phase;
  final Map<String, dynamic>? gameOver;

  bool get isGameOver => gameOver != null;
  String? get winnerID => gameOver?['winner'];
  bool get isDraw => gameOver?['draw'] ?? false;
}

class Client<G extends Game> {
  Client({
    required this.lobby,
    required this.game,
    required this.playerID,
    required this.credentials,
    Uri? uri,
  }) : this.uri = uri ?? lobby.uri;

  final Uri uri;
  final Lobby lobby;
  final G game;
  final String playerID;
  final String credentials;

  int _stateID = -1;
  // dynamic _matchData;

  IO.Socket? _socket;
  void Function(Map<String, dynamic> G, ClientContext ctx) _subscriber = (_, __) {};

  void start() {
    if (this._socket == null) {
      String gameServer = uri.resolve(game.description.name).toString();
      final socket = IO.io(gameServer, IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build());
      this._socket = socket;
      socket.onConnect((data) {
        // print('SOCKET.onConnect(${data.toString()})');
        _sync();
      });
      socket.onDisconnect((data) {
        // print('SOCKET.onDisconnect(${data.toString()})');
      });
      socket.on('update', (data) => _update('update', data[0], data[1]));
      socket.on('sync', (data) => _update('sync', data[0], data[1]['state']));
      socket.on('matchData', (data) {
        // print('SOCKET.on(matchData, ${data.toString()})');
        // this._matchData = data;
      });
      socket.open();
    }
  }

  void _update(String opName, String matchID, Map<String,dynamic> state) {
    if (matchID != this.game.matchID) {
      print('$opName sent to wrong match ($matchID != ${this.game.matchID})');
      return;
    }

    int stateID = state['_stateID'];
    if (stateID < this._stateID) {
      print('${opName.toUpperCase()} GOT OLD STATE ID: $stateID < ${this._stateID}');
    }
    _stateID = state['_stateID'];

    _subscriber(state['G'], ClientContext._fromJson(state['ctx']));
  }

  void subscribe(
      void update(
          Map<String, dynamic> G,
          ClientContext ctx
          ),
      ) {
    _subscriber = update;
  }

  void _sync() {
    // print('syncing: '+[ game.matchID, this.playerID, game.description.numPlayers ].toString());
    _socket!.emit('sync', [game.matchID, this.playerID, game.description.numPlayers ]);
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }

  void makeMove(String moveName, List<dynamic> args) {
    _socket!.emit('update', [
      {
        'type': 'MAKE_MOVE',
        'payload': {
          'type': moveName,
          'args': args,
          'playerID': this.playerID,
          'credentials': this.credentials,
        },
      },
      this._stateID,
      game.matchID,
      this.playerID,
    ]);
  }

  Future<void> leaveGame() async {
    stop();
    await lobby.leaveGame(this);
  }
}
