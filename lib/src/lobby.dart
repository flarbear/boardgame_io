/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

import 'client.dart';
import 'game.dart';
import 'io/io.dart';
import 'player.dart';
import 'server_state.dart';

/// Provides all information tracked about a given Lobby Match.
class MatchData {
  MatchData._({
    required this.gameName,
    required this.matchID,
    required List<Player> players,
    this.unlisted = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.setupData,
    this.gameOver,
  })
      : this.players = List.unmodifiable(players),
        this.createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        this.updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory MatchData._fromJson(Map<String, dynamic> jsonData) {
    return MatchData._(
      gameName:  jsonData['gameName']!,
      matchID:   jsonData['matchID']!,
      unlisted:  jsonData['unlisted'] || false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(jsonData['createdAt'] ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(jsonData['updatedAt'] ?? 0),
      setupData: jsonData['setupData'],
      players:   (jsonData['players']! as List<dynamic>).map((playerInfo) {
        return Player.fromJson(playerInfo as Map<String, dynamic>);
      }).toList(growable: false),
      gameOver:  jsonData['gameover'],
    );
  }

  /// The protocol-level name of the game for which this match was constructed.
  final String gameName;

  /// The protocol-level ID used by the lobby to track this specific match.
  final String matchID;

  /// The players currently associated with this match.
  final List<Player> players;

  /// Whether this match is unlisted (typically `true` for matches created
  /// outside of the lobby).
  final bool unlisted;

  /// The date and time when this match was created.
  final DateTime createdAt;

  /// The date and time of the last update to this match.
  final DateTime updatedAt;

  /// The setupData passed when this match was created.
  final Map<String, dynamic>? setupData;

  /// When not null, the game is over and the map will contain information
  /// about the results.
  ///
  /// Typically a game that was won will contain the playerID of the winner
  /// in a `winner` field, as in `gameOver['winner'] = winnerID;`
  /// Typically a game that is a draw will contain a boolean in a `draw`
  /// field, as in `gameOver['draw'] = true;`
  final Map<String, dynamic>? gameOver;

  /// True iff the game is not over and there is an unseated player slot
  /// remaining in the [players] list.
  bool get canJoin => (gameOver == null && players.any((player) => !player.isSeated));

  /// Returns a [Game] object representing this match.
  Game toGame() {
    return Game(GameDescription(gameName, players.length), matchID);
  }

  /// Converts this match to a custom [String] that uses the [playerInit],
  /// [playerJoin] and [playerEnd] strings to concatenate the list of
  /// players, as in `$playerInit$player1$playerJoin$player2$playerJoin$player3$playerEnd`.
  String toCustomString(String playerInit, String playerJoin, String playerEnd) {
    return 'Match(id: $matchID, created: ${createdAt.toLocal()}, players: [$playerInit${players.join(playerJoin)}$playerEnd])';
  }

  /// Converts this match to a multi-line [String] at the indicated level
  /// of [outerIndent] spaces with an additional [innerIndent] spaces for
  /// the continuation lines of the [Player] list.
  String toMultilineString([ int outerIndent = 0, int innerIndent = 2 ]) {
    String outer = ''.padLeft(outerIndent, ' ');
    String inner = outer.padRight(outerIndent + innerIndent, ' ');
    return toCustomString('\n$inner', ',\n$inner', ',\n$outer');
  }

  /// Converts this match to a simple single-line [String] with simple
  /// commas separating the entries in the list of [Player]s.
  @override
  String toString() {
    return toCustomString('', ', ', '');
  }
}

/// The Lobby class will connect to a boardgame.io server at the indicated [Uri]
/// and provide information about the matches being managed by that server.
class Lobby {
  /// Construct a Lobby for the boardgame.io server at the indicated [Uri] with
  /// optionally specified timeouts for how often a network request is used to
  /// refresh the list of games or the list of matches.
  Lobby(this.uri, {
    Duration? gameFreshness,
    Duration? matchFreshness,
  })
      : this.gameFreshness = gameFreshness ?? Duration(days: 1),
        this.matchFreshness = matchFreshness ?? Duration(seconds: 5);

  /// The Uri of the boardgame.io server.
  final Uri uri;

  Future<dynamic> _getBody(String relativeUrl) async {
    return io.getBody(uri.resolve(relativeUrl));
  }

  Future<dynamic> _postBody(String relativeUrl, Map<String, dynamic> parameters) async {
    return io.postBody(uri.resolve(relativeUrl), parameters);
  }

  Future<List<String>> _loadGames(List<String>? prev) async {
    return (await _getBody('games') as List<dynamic>).map((name) => name.toString()).toList(growable: false);
  }

  /// The expiration duration for how often the list of games will be refreshed.
  final Duration gameFreshness;
  late RefreshableState<List<String>> _gameState = RefreshableState(gameFreshness, _loadGames);

  /// Return the list of games managed by the boardgame.io server, as of no more
  /// than [gameFreshness] since the last network request unless [force] is true.
  Future<List<String>> listGames({ bool force = false, }) async => _gameState.get(force: force);

  Future<List<MatchData>> _loadMatches(gameName) async {
    Map<String, dynamic> replyBody = await _getBody('games/$gameName') as Map<String, dynamic>;
    return (replyBody['matches'] as List<dynamic>).map((matchData) {
      return MatchData._fromJson(matchData as Map<String, dynamic>);
    }).toList(growable: false);
  }

  /// The expiration duration for how often the list of matches for a given game
  /// will be refreshed.
  final Duration matchFreshness;
  Map<String, RefreshableState<List<MatchData>>> _matchStates = <String, RefreshableState<List<MatchData>>>{};

  /// Return the list of matches for the specified game, as of no more than
  /// [matchFreshness] since the last network request unless [force] is true.
  Future<List<MatchData>> listMatches(String gameName, { bool force = false, }) async {
    RefreshableState<List<MatchData>>? state = _matchStates[gameName];
    if (state == null) {
      state = RefreshableState<List<MatchData>>(matchFreshness, (prev) => _loadMatches(gameName));
      _matchStates[gameName] = state;
    }
    return state.get(force: force);
  }

  /// Return the information associated with the given game name and ID, as of
  /// no more than [matchFreshness] since the last network request unless [force]
  /// is true.
  Future<MatchData?> getMatch(String gameName, String matchID, { bool force = false, }) async {
    List<MatchData> matchList = await listMatches(gameName, force: force);
    for (MatchData matchData in matchList) {
      if (matchData.matchID == matchID) {
        return matchData;
      }
    }
    return null;
  }

  /// Create a new match according to the information in [game] and return the
  /// [MatchData] associated with the new match.
  Future<MatchData> createMatch(GameDescription game) async {
    Map<String, dynamic> replyBody = await _postBody('games/${game.name}/create', {
      'numPlayers': game.numPlayers,
      if (game.setupData != null)
        'setupData': game.setupData,
    }) as Map<String, dynamic>;
    return (await getMatch(game.name, replyBody['matchID'], force: true))!;
  }

  /// Create a [Client] to observe the indicated game match without registering
  /// as a [Player].
  Client watchMatch(Game game) {
    return Client(
      lobby: this,
      game: game,
    );
  }

  /// Create a [Client] to participate in the indicated game match registered
  /// as the indicated [playerID] with the indicated player [name].
  Future<Client> joinMatch(Game game, String playerID, String name) async {
    Map<String, dynamic> replyBody = await _postBody('games/${game.description.name}/${game.matchID}/join', {
      'playerID': playerID,
      'playerName': name,
    }) as Map<String, dynamic>;
    return Client(
      lobby: this,
      game: game,
      playerID: playerID,
      credentials: replyBody['playerCredentials'],
    );
  }

  /// Inform the server that the indicated credentialed player is officially
  /// leaving the game, leaving the seat open if another player wishes to join.
  Future<void> leaveGame(Client gameClient) async {
    String? playerID = gameClient.playerID;
    String? credentials = gameClient.credentials;
    if (playerID != null && credentials != null) {
      Game game = gameClient.game;
      await _postBody('games/${game.description.name}/${game.matchID}/leave', {
        'playerID': playerID,
        'credentials': credentials,
      });
    }
  }

  /// Close any ongoing lobby connections to the boardgame.io server.
  void close() {
    // Will be useful if/when the HTTP Client gets reused between requests...
  }
}
