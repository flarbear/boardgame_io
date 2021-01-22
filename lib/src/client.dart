/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'game.dart';
import 'lobby.dart';
import 'player.dart';

final Logger _clientLog = Logger('Client');

List<String> _toStringList(List<dynamic> rawList) => rawList.map<String>((e) => e.toString()).toList();

/// The information provided by a boardgame.io match about the current
/// game progress, as is usually tracked by the 'ctx' argument in the
/// boardgame.io documentation and examples.
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
    if (_clientLog.isLoggable(Level.FINE)) {
      _clientLog.fine('ctx: '+JsonEncoder.withIndent('  ').convert(jsonData));
    }
  }

  /// The number of players in the game.
  final int numPlayers;

  /// The turn counter for the game.
  final int turn;

  /// The ID of the player whose turn it is.
  final String currentPlayer;

  /// The IDs of the players in order of their turns.
  final List<String> playerOrder;

  /// The position in the playerOrder for the current turn.
  final int playOrderPos;

  /// The name of the current game phase, or `null` for the default phase.
  final String? phase;

  /// Information about the end of the game if it is over.
  final Map<String, dynamic>? gameOver;

  /// True iff the game is over.
  bool get isGameOver => gameOver != null;

  /// The protocol-level ID of the winner if the game is over and there was a winner.
  String? get winnerID => gameOver?['winner'];

  /// True iff the game is over and the result was a draw or stalemate.
  bool get isDraw => gameOver?['draw'] ?? false;
}

/// The Client class will maintain a connection to a boardgame.io server
/// to either observe the specified match in a "spectator" role, or to
/// participate using the indicated [playerID] and [credentials].
class Client<GAME extends Game> {
  Client({
    required this.lobby,
    required this.game,
    this.playerID,
    this.credentials,
    Uri? uri,
  }) : this.uri = uri ?? lobby.uri;

  /// The Uri of the boardgame.io server managing this game.
  final Uri uri;

  /// The Lobby used to join this game.
  final Lobby lobby;

  /// The [Game] object describing the game being played.
  final GAME game;

  /// The ID of the player participating in this game, or `null` if this is a
  /// spectator client.
  final String? playerID;

  /// The credentials that enable the client to participate in the game,
  /// or `null` if this is a spectator client.
  final String? credentials;

  /// The list of [Player]s participating in this game, indexed by either
  /// their position in the list or by their playerID.
  Map<dynamic, Player> _players = <dynamic,Player>{};
  Map<dynamic, Player> get players => _players;

  String get playerName => players[playerID]?.name ?? 'Spectator';

  int _stateID = -1;
  Map<String, dynamic>? _G;
  ClientContext? _ctx;

  IO.Socket? _socket;
  void Function(Map<String, dynamic> G, ClientContext ctx) _subscriber = (_, __) {};

  /// Start the game client and connect to the boardgame.io server.
  void start() {
    if (this._socket == null) {
      String gameServer = uri.resolve(game.description.name).toString();
      final socket = IO.io(gameServer, IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build());
      this._socket = socket;
      socket.onConnect((data) {
        _clientLog.fine('SOCKET.onConnect(${data.toString()})');
        _sync();
      });
      socket.onDisconnect((data) {
        _clientLog.fine('SOCKET.onDisconnect(${data.toString()})');
      });
      socket.on('update', (data) => _update('update', data[0], data[1]));
      socket.on('sync', (data) => _update('sync', data[0], data[1]['state']));
      socket.on('matchData', (data) {
        _clientLog.fine('SOCKET.on(matchData, ${JsonEncoder.withIndent('  ').convert(data)})');
        if (data[0] != this.game.matchID) {
          _clientLog.warning('matchData sent to wrong match (${data[0]} != ${this.game.matchID})');
          return;
        }
        Map<dynamic, Player> newPlayers = <dynamic,Player>{};
        for (int i = 0; i < data[1].length; i++) {
          Player player = Player.fromJson(data[1][i]);
          newPlayers[i] = player;
          newPlayers[player.id] = player;
        }
        _players = newPlayers;
        _notify();
      });
      socket.open();
    }
  }

  void _update(String opName, String matchID, Map<String,dynamic> state) {
    if (matchID != this.game.matchID) {
      _clientLog.warning('$opName sent to wrong match ($matchID != ${this.game.matchID})');
      return;
    }

    int stateID = state['_stateID'];
    if (stateID < this._stateID) {
      _clientLog.warning('${opName.toUpperCase()} GOT OLD STATE ID: $stateID < ${this._stateID}');
    }

    _stateID = stateID;
    _G = state['G'];
    _ctx = ClientContext._fromJson(state['ctx']);

    _notify();
  }

  void _notify() {
    Map<String, dynamic>? G = _G;
    ClientContext? ctx = _ctx;
    if (G != null && ctx != null) {
      _subscriber(G, ctx);
    }
  }

  /// Subscribe to the client for updates on the game state with a callback function.
  ///
  /// The game state is provided to the callback in two main structures:
  /// - [G]: the "board" state of the game, where pieces and cards have been played, etc.
  /// - [ctx]: the "progress" state of the game, which phase the game is in and whose turn, etc.
  void subscribe(
      void update(
          Map<String, dynamic> G,
          ClientContext ctx,
          ),
      ) {
    _subscriber = update;
  }

  void _sync() {
    _clientLog.fine('syncing: '+[ game.matchID, this.playerID, game.description.numPlayers ].toString());
    _socket!.emit('sync', [game.matchID, this.playerID, game.description.numPlayers ]);
  }

  /// Stop the client and close the client network connection to the boardgame.io
  /// server, but do not relinquish the seat.
  ///
  /// No other [Client] will be able to connect to the same seat in the match without
  /// the proper [credentials], so this should only be a temporary closure unless the
  /// player leaves the game using the [Lobby.leaveGame] method.
  void stop() {
    _socket?.close();
    _socket = null;
  }

  /// Send a generic move request to the boardgame.io server.
  ///
  /// This is a utility method used by a generic game [Client] to communicate
  /// moves without any type-checking. More specific moves should be provided
  /// as methods in subclasses to facilitate strongly typed game play.
  void makeMove(String moveName, [ List<dynamic>? args = null, ]) {
    _socket!.emit('update', [
      {
        'type': 'MAKE_MOVE',
        'payload': {
          'type': moveName,
          'args': args ?? [],
          'playerID': this.playerID,
          'credentials': this.credentials,
        },
      },
      this._stateID,
      game.matchID,
      this.playerID,
    ]);
  }

  /// Update the name for this player, notifying the other players
  /// via the lobby.
  Future<void> updateName(String newName) async {
    await lobby.updatePlayer(this, newName);
  }

  /// Stop this client and relinquish the seat in this match (if the
  /// [Client] joined as a player rather than a spectator).
  Future<void> leaveGame() async {
    stop();
    if (playerID != null) {
      await lobby.leaveGame(this);
    }
  }
}
