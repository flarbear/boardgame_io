/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

import 'dart:async';
import 'dart:io';

import 'package:boardgame_io/boardgame.dart';

var playerName = 'unknown';

bool updatePlayerName() {
  stdout.write('Enter name: ');
  String? newName = stdin.readLineSync();
  if (newName == null) return false;
  playerName = newName;
  return true;
}

void quit() {
  throw 'quit';
}

void main(List<String> args) async {
  if (args.length == 1) {
    playerName = args[0];
  } else {
    if (!updatePlayerName()) return;
  }
  Lobby lobby = Lobby(Uri.parse('http://localhost:8000'));
  final List<String> games = await lobby.listGames();
  print('The server supports the following games: '+games.join(', '));
  setupStdin();
  List<Client> clients = <Client>[];
  try {
    while (await pickGame(lobby, games)) {}
  } catch (e, stack) {
    if (e != 'quit') {
      print(e);
      print(stack);
    }
  }
  for (Client client in clients) {
    try {
      print('Leaving client: '+client.toString());
      await client.leaveGame();
    } catch (e) {
      print(e);
    }
  }
  resetStdin();
  lobby.close();
}

const int cUpper = 67;
const int cLower = cUpper + 32;
const int qUpper = 81;
const int qLower = qUpper + 32;
const int rUpper = 82;
const int rLower = rUpper + 32;
const int digit0 = 48;
const int digit9 = digit0 + 9;

Completer<int>? _stdinCompleter;
StreamSubscription<List<int>>? _stdinListener;

void setupStdin() {
  stdin.echoMode = false;
  stdin.lineMode = false;
  _stdinListener = stdin.listen((event) {
    _stdinCompleter?.complete(event.last);
    _stdinCompleter = null;
  });
}

void resetStdin() {
  stdin.lineMode = true;
  stdin.echoMode = true;
  _stdinListener?.cancel();
}

Future<int> nextChar() async {
  Completer<int> completer = Completer<int>();
  _stdinCompleter = completer;
  return completer.future;
}

Future<int> choose(String type, List<dynamic> options, [ bool allowCreate = false ]) async {
  print('');
  if (options.isNotEmpty) {
    print('Pick a $type:');
    for (int i = 0; i < options.length; i++) {
      if (i > 9) {
        print('  (Some ${type}s omitted...)');
        break;
      }
      print('  $i: ${options[i].toString()}');
    }
    if (allowCreate) {
      print("Or type 'c' or 'C' to create a new $type.");
    }
  } else if (allowCreate) {
    print("Type 'c' or 'C' to create a new $type.");
  } else {
    print('No $type options to choose!');
    quit();
  }
  print("Or type 'q' or 'Q' to quit.");
  while (true) {
    stdout.write('[qQ');
    if (allowCreate) stdout.write('Cc');
    for (int i = 0; i < options.length && i <= 9; i++) stdout.write(i.toString());
    stdout.write(']> ');
    int input = await nextChar();
    stdout.writeCharCode(input);
    stdout.write('\n');
    if (input < 0 || input == qUpper || input == qLower) quit();
    if (allowCreate && (input == cUpper || input == cLower)) return options.length;
    if (input >= digit0 && input <= digit9 && input - digit0 < options.length) {
      return input - digit0;
    }
    stdout.write('bad input: ');
    stdout.writeCharCode(input);
    stdout.writeln();
  }
}

Future<bool> pickGame(Lobby lobby, List<String> gameNames) async {
  if (gameNames.isEmpty) {
    print('No games supported, exiting');
    quit();
  }
  int index = gameNames.length < 2 ? 0 : await choose('game', gameNames);
  return pickMatch(lobby, gameNames[index]);
}

Future<bool> pickMatch(Lobby lobby, String gameName) async {
  List<MatchData> matches = await lobby.listMatches(gameName, force: true);
  int index = await choose('match', matches, true);
  if (index < matches.length) {
    return pickSeat(lobby, matches[index]);
  } else {
    return createMatch(lobby, gameName);
  }
}

Future<bool> createMatch(Lobby lobby, String gameName) async {
  GameDescription desc = GameDescription(gameName, 2);
  MatchData match = await lobby.createMatch(desc);
  return joinMatch(lobby, match, match.players[0].id);
}

Future<bool> pickSeat(Lobby lobby, MatchData matchData) async {
  List<String> openSeats = matchData.players
      .where((player) => player.name == null)
      .map((player) => player.id)
      .toList();
  if (openSeats.isEmpty) {
    print('There are no open seats in $matchData');
    return true;
  }
  int index = await choose('seat', openSeats.map((id) => 'Seat $id').toList());
  return await joinMatch(lobby, matchData, openSeats[index]);
}

String xo(List<dynamic> cells, int index) {
  dynamic cell = cells[index];
  if (cell == null) return (index+1).toString();
  if (cell == '0') return 'X';
  if (cell == '1') return 'O';
  return '?';
}

Future<bool> joinMatch(Lobby lobby, MatchData matchData, String playerID) async {
  Client client = await lobby.joinMatch(matchData.toGame(), playerID, playerName);
  final List<int> validMoves = [];
  client.subscribe((Map<String, dynamic> G, Map<String, dynamic> ctx) {
    validMoves.clear();
    print('\n');
    dynamic gameOver = ctx['gameover'];
    dynamic winner = gameOver?['winner'];
    if (gameOver == null) {
      List<dynamic> cells = G['cells'];
      print(' ${xo(cells, 0)} | ${xo(cells, 1)} | ${xo(cells, 2)}');
      print('---+---+---');
      print(' ${xo(cells, 3)} | ${xo(cells, 4)} | ${xo(cells, 5)}');
      print('---+---+---');
      print(' ${xo(cells, 6)} | ${xo(cells, 7)} | ${xo(cells, 8)}');
      for (int i = 0; i < cells.length; i++) {
        if (cells[i] == null) validMoves.add(i+1);
      }
    } else if (winner != null) {
      print('Game over: ${xo([winner], 0)} won!');
    } else {
      print('Game over: $gameOver');
    }
    if (gameOver != null || ctx['currentPlayer'] == client.playerID) {
      stdout.write('Enter move: [qQ${gameOver == null ? '' : 'rR'}${validMoves.join('')}]: ');
    } else {
      stdout.write('Wait for the other player to move...');
    }
  });
  client.start();
  try {
    while (true) {
      int move = await nextChar();
      if (move == qLower || move == qUpper) {
        return false;
      }
      if (move == rLower || move == rUpper) {
        return true;
      }
      if (validMoves.contains(move - digit0)) {
        client.makeMove('clickCell', [ move - digit0 - 1]);
        continue;
      }
      stdout.write('bad input: ');
      stdout.writeCharCode(move);
      stdout.writeln();
    }
  } finally {
    client.leaveGame();
  }
}
