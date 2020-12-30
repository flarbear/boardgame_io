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

  factory LobbyPlayer._fromJson(Map<String, dynamic> jsonData) {
    return LobbyPlayer(jsonData['id']!.toString(),
      name: jsonData['name'],
      isConnected: jsonData['isConnected'] ?? false,
    );
  }

  final String id;

  String? _name;
  String? get name => _name;

  bool get isSeated => name != null;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  @override
  String toString() {
    return 'LobbyPlayer(id=$id, name=${name ?? '<empty>'}, isConnected=$isConnected)';
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

class Match {
  Match._({
    required this.gameName,
    required this.matchID,
    required List<LobbyPlayer> players,
    this.unlisted = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.setupData,
  })
      : this.players = List.unmodifiable(players),
        this.createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        this.updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory Match._fromJson(Map<String, dynamic> jsonData) {
    return Match._(
      gameName:  jsonData['gameName']!,
      matchID:   jsonData['matchID']!,
      unlisted:  jsonData['unlisted'] || false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(jsonData['createdAt'] ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(jsonData['updatedAt'] ?? 0),
      setupData: jsonData['setupData'],
      players:   (jsonData['players']! as List<dynamic>).map((playerInfo) {
        return LobbyPlayer._fromJson(playerInfo as Map<String, dynamic>);
      }).toList(growable: false),
    );
  }

  final String gameName;
  final String matchID;
  final List<LobbyPlayer> players;
  final bool unlisted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? setupData;

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
        this.matchFreshness = matchFreshness ?? Duration(seconds: 5),
        this.httpClient = httpClient ?? HttpClient();

  HttpClient? httpClient;
  Uri uri;

  Future<dynamic> _getBody(String relativeUrl) async {
    HttpClientRequest request = await httpClient!.getUrl(uri.resolve(relativeUrl));
    HttpClientResponse response = await request.close();
    return JsonDecoder().convert(await response.transform(utf8.decoder).join());
  }

  Future<dynamic> _postBody(String relativeUrl, Map<String, dynamic> body) async {
    HttpClientRequest request = await httpClient!.postUrl(uri.resolve(relativeUrl));
    request.headers.contentType = ContentType.json;
    request.write(JsonEncoder().convert(body));
    HttpClientResponse response = await request.close();
    return JsonDecoder().convert(await response.transform(utf8.decoder).join());
  }

  Future<List<String>> _loadGames(List<String>? prev) async {
    return (await _getBody('games') as List<dynamic>).map((name) => name.toString()).toList(growable: false);
  }

  final Duration? gameFreshness;
  late RefreshableState<List<String>> _gameState = RefreshableState(gameFreshness!, _loadGames);
  Future<List<String>> games({ bool force = false, }) async => _gameState.get(force: force);

  Future<List<Match>> _loadMatches(gameName) async {
    Map<String, dynamic> replyBody = await _getBody('games/$gameName') as Map<String, dynamic>;
    return (replyBody['matches'] as List<dynamic>).map((matchData) {
      return Match._fromJson(matchData as Map<String, dynamic>);
    }).toList(growable: false);
  }

  final Duration? matchFreshness;
  Map<String, RefreshableState<List<Match>>> _matchStates = <String, RefreshableState<List<Match>>>{};
  Future<List<Match>> matches(String gameName, { bool force = false, }) async {
    RefreshableState<List<Match>>? state = _matchStates[gameName];
    if (state == null) {
      state = RefreshableState<List<Match>>(matchFreshness!, (prev) => _loadMatches(gameName));
      _matchStates[gameName] = state;
    }
    return state.get(force: force);
  }

  Future<Match?> getMatch(String gameName, String matchID, { bool force = false, }) async {
    List<Match> matchList = await matches(gameName, force: force);
    for (Match match in matchList) {
      if (match.matchID == matchID) {
        return match;
      }
    }
    return null;
  }

  Future<Game> createGame(GameDescription game) async {
    Map<String, dynamic> replyBody = await _postBody('games/${game.name}/create', {
      'numPlayers': game.numPlayers,
    }) as Map<String, dynamic>;
    return game.makeGame(replyBody['matchID']);
  }

  Future<Client> joinGame(Game game, String playerID, String name) async {
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
    httpClient?.close(force: true);
    httpClient = null;
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
    List<String> gameNames = await lobby.games();
    print('Server provides games: ${gameNames.join(', ')}');
    for (String gameName in gameNames) {
      if (create) {
        GameDescription gameDesc = GameDescription(gameName, 2);
        Game game = await lobby.createGame(gameDesc);
        print('Created: ${game.matchID}');
      }
      List<Match> matches = await lobby.matches(gameName);
      List<Client> clients = <Client>[];
      if (join) {
        for (Match match in matches) {
          for (LobbyPlayer player in match.players) {
            if (!player.isSeated) {
              print('test joining ${match.matchID}/${player.id} as "TEST JOIN"');
              clients.add(await lobby.joinGame(match.toGame(), player.id, 'TEST JOIN'));
              break;
            }
          }
        }
        if (clients.isNotEmpty) {
          matches = await lobby.matches(gameName, force: true);
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
