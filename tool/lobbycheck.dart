/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

import '../lib/boardgame.dart';

bool _checkArg(List<String> args, String flag) {
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
  bool create = _checkArg(args, '--create');
  bool join = _checkArg(args, '--join');
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
          for (Player player in matchData.players) {
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
