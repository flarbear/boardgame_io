/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

import 'dart:convert';
import 'dart:io';

import './client.dart';
import './game.dart';
import './server_state.dart';

class LobbyPlayer {
  LobbyPlayer(this.id, { String? name, bool isConnected = false })
      : this._name = name,
        this._isConnected = isConnected;

  factory LobbyPlayer.fromJson(Map<String, dynamic> jsonData) {
    return LobbyPlayer(jsonData['id']!.toString(),
      name: jsonData['name'],
      isConnected: jsonData['isConnected'] ?? false,
    );
  }

  final String id;

  String? _name;
  String? get seatedName => _name;
  String get name => _name ?? 'Player $id';

  bool get isSeated => _name != null;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  @override
  String toString() {
    return 'LobbyPlayer(id=$id${isSeated ? ', name=${_name}, isConnected=$isConnected' : ''})';
  }

  @override
  int get hashCode {
    return id.hashCode;
  }

  @override
  bool operator ==(Object other) {
    return (other is LobbyPlayer) && id == other.id;
  }
}

class MatchData {
  MatchData._({
    required this.gameName,
    required this.matchID,
    required List<LobbyPlayer> players,
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
        return LobbyPlayer.fromJson(playerInfo as Map<String, dynamic>);
      }).toList(growable: false),
      gameOver:  jsonData['gameover'],
    );
  }

  final String gameName;
  final String matchID;
  final List<LobbyPlayer> players;
  final bool unlisted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? setupData;
  final Map<String, dynamic>? gameOver;

  bool get canJoin => (gameOver == null && players.any((player) => !player.isSeated));

  Game toGame() {
    return Game(GameDescription(gameName, players.length), matchID);
  }

  String toCustomString(String playerInit, String playerJoin, String playerEnd) {
    return 'Match(id: $matchID, created: ${createdAt.toLocal()}, players: [$playerInit${players.join(playerJoin)}$playerEnd])';
  }

  String toMultilineString([ int outerIndent = 0, int innerIndent = 2 ]) {
    String outer = ''.padLeft(outerIndent, ' ');
    String inner = outer.padRight(outerIndent + innerIndent, ' ');
    return toCustomString('\n$inner', ',\n$inner', ',\n$outer');
  }

  @override
  String toString() {
    return toCustomString('', ', ', '');
  }
}

class Lobby {
  Lobby(this.uri, {
    Duration? gameFreshness,
    Duration? matchFreshness,
    HttpClient? httpClient,
  })
      : this.gameFreshness = gameFreshness ?? Duration(days: 1),
        this.matchFreshness = matchFreshness ?? Duration(seconds: 5);

  Uri uri;

  Future<T> _withClient<T>(Future<T> fn(HttpClient)) async {
    final HttpClient client = HttpClient();
    try {
      return await fn(client);
    } finally {
      client.close();
    }
  }

  Future<dynamic> _getBody(String relativeUrl) => _withClient((httpClient) async {
    HttpClientRequest request = await httpClient.getUrl(uri.resolve(relativeUrl));
    HttpClientResponse response = await request.close();
    String reply = await response.transform(utf8.decoder).join();
    return JsonDecoder().convert(reply);
  });

  Future<dynamic> _postBody(String relativeUrl, Map<String, dynamic> parameters) => _withClient((httpClient) async {
    Uri absoluteUri = uri.resolve(relativeUrl);
    HttpClientRequest request = await httpClient.postUrl(absoluteUri);
    request.headers.contentType = ContentType.json;
    String bodyString = JsonEncoder().convert(parameters);
    request.write(bodyString);
    HttpClientResponse response = await request.close();
    String reply = await response.transform(utf8.decoder).join();
    return JsonDecoder().convert(reply);
  });

  Future<List<String>> _loadGames(List<String>? prev) async {
    return (await _getBody('games') as List<dynamic>).map((name) => name.toString()).toList(growable: false);
  }

  final Duration? gameFreshness;
  late RefreshableState<List<String>> _gameState = RefreshableState(gameFreshness!, _loadGames);
  Future<List<String>> listGames({ bool force = false, }) async => _gameState.get(force: force);

  Future<List<MatchData>> _loadMatches(gameName) async {
    Map<String, dynamic> replyBody = await _getBody('games/$gameName') as Map<String, dynamic>;
    return (replyBody['matches'] as List<dynamic>).map((matchData) {
      return MatchData._fromJson(matchData as Map<String, dynamic>);
    }).toList(growable: false);
  }

  final Duration? matchFreshness;
  Map<String, RefreshableState<List<MatchData>>> _matchStates = <String, RefreshableState<List<MatchData>>>{};
  Future<List<MatchData>> listMatches(String gameName, { bool force = false, }) async {
    RefreshableState<List<MatchData>>? state = _matchStates[gameName];
    if (state == null) {
      state = RefreshableState<List<MatchData>>(matchFreshness!, (prev) => _loadMatches(gameName));
      _matchStates[gameName] = state;
    }
    return state.get(force: force);
  }

  Future<MatchData?> getMatch(String gameName, String matchID, { bool force = false, }) async {
    List<MatchData> matchList = await listMatches(gameName, force: force);
    for (MatchData matchData in matchList) {
      if (matchData.matchID == matchID) {
        return matchData;
      }
    }
    return null;
  }

  Future<MatchData> createMatch(GameDescription game) async {
    Map<String, dynamic> replyBody = await _postBody('games/${game.name}/create', {
      'numPlayers': game.numPlayers,
    }) as Map<String, dynamic>;
    return (await getMatch(game.name, replyBody['matchID'], force: true))!;
  }

  Client watchMatch(Game game) {
    return Client(
      lobby: this,
      game: game,
    );
  }

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

  Future<void> leaveGame(Client gameClient) async {
    Game game = gameClient.game;
    await _postBody('games/${game.description.name}/${game.matchID}/leave', {
      'playerID': gameClient.playerID,
      'credentials': gameClient.credentials,
    });
  }

  void close() {
  }
}

bool checkArg(List<String> args, String flag) {
  bool contains = args.contains(flag);
  if (contains) {
    args.remove(flag);
  }
  return contains;
}

/// Test code to list all matches from all games supported by a list of boardgame.io
/// servers provided by URL as command-line arguments.
main(List<String> args) async {
  args = [ ...args ];
  bool create = checkArg(args, '--create');
  bool join = checkArg(args, '--join');
  if (args.length == 0) {
    print('usage: dart lobby.dart <game-server-url>');
  }
  for (String host in args) {
    print('Processing host: "$host"');
    Lobby lobby = Lobby(Uri.parse(host));
    List<String> gameNames = await lobby.listGames();
    print('Server provides games: ${gameNames.join(', ')}');
    for (String gameName in gameNames) {
      if (create) {
        GameDescription gameDesc = GameDescription(gameName, 2);
        MatchData match = await lobby.createMatch(gameDesc);
        print('Created: ${match.matchID}');
      }
      List<MatchData> matches = await lobby.listMatches(gameName);
      List<Client> clients = <Client>[];
      if (join) {
        for (MatchData matchData in matches) {
          for (LobbyPlayer player in matchData.players) {
            if (!player.isSeated) {
              print('test joining ${matchData.matchID}/${player.id} as "TEST JOIN"');
              clients.add(await lobby.joinMatch(matchData.toGame(), player.id, 'TEST JOIN'));
              break;
            }
          }
        }
        if (clients.isNotEmpty) {
          matches = await lobby.listMatches(gameName, force: true);
        }
      }
      // print('$gameName matches: [');
      // matches.forEach((match) { print('  ${match.toString()},'); });
      // print(']');
      print('$gameName matches: [');
      matches.forEach((match) { print('  ${match.toMultilineString(2, 2)},'); });
      print(']');
      for (Client gameClient in clients) {
        print('leaving: ${gameClient.game.matchID}/${gameClient.playerID}');
        await gameClient.leaveGame();
      }
    }
    print('closing lobby');
    lobby.close();
  }
}
