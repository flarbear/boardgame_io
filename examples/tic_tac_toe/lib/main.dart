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

void returnToLobby() {
  throw 'refresh';
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
  while (true) {
    try {
      await pickGame(lobby, games);
    } catch (e, stack) {
      if (e == 'quit') break;
      if (e == 'refresh') continue;
      print(e);
      print(stack);
      break;
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
  if (_stdinCompleter != null) {
    throw 'Unexpected nested calls to nextChar()';
  }
  Completer<int> completer = Completer<int>();
  _stdinCompleter = completer;
  int input = await completer.future;
  stdout.writeCharCode(input);
  stdout.write('\n');
  if (input < 0 || input == qUpper || input == qLower) quit();
  if (input == rUpper || input == rLower) returnToLobby();
  return input;
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
  print("Or type 'r' or 'R' to return and refresh lobby.");
  while (true) {
    stdout.write('[QqRr');
    if (allowCreate) stdout.write('Cc');
    for (int i = 0; i < options.length && i <= 9; i++) stdout.write(i.toString());
    stdout.write(']> ');
    int input = await nextChar();
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
  List<MatchData> matches = (await lobby.listMatches(gameName, force: true))
      .where((match) => match.canJoin)
      .toList();
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

String xop(String playerID) {
  if (playerID == '0') return 'X';
  if (playerID == '1') return 'O';
  return '?';
}

String xoc(List<dynamic> cells, int index) {
  dynamic cell = cells[index];
  if (cell is String) return xop(cell);
  return (index+1).toString();
}

Future<bool> joinMatch(Lobby lobby, MatchData matchData, String playerID) async {
  Client client = await lobby.joinMatch(matchData.toGame(), playerID, playerName);
  final List<int> validMoves = [];
  String prompt = '';
  client.subscribe((Map<String, dynamic> G, Map<String, dynamic> ctx) {
    validMoves.clear();
    print('\n');
    dynamic gameOver = ctx['gameover'];
    dynamic winner = gameOver?['winner'];
    dynamic isDraw = gameOver?['draw'] ?? false;
    List<dynamic> cells = G['cells'];
    print(' ${xoc(cells, 0)} | ${xoc(cells, 1)} | ${xoc(cells, 2)}');
    print('---+---+---');
    print(' ${xoc(cells, 3)} | ${xoc(cells, 4)} | ${xoc(cells, 5)}');
    print('---+---+---');
    print(' ${xoc(cells, 6)} | ${xoc(cells, 7)} | ${xoc(cells, 8)}');
    if (gameOver == null) {
      for (int i = 0; i < cells.length; i++) {
        if (cells[i] == null) validMoves.add(i + 1);
      }
      if (ctx['currentPlayer'] == client.playerID) {
        prompt = '${xop(client.playerID)} - Enter move: [QqRr${gameOver == null ? '' : 'rR'}${validMoves.join('')}]> ';
      } else {
        prompt = 'Waiting for ${xop(ctx['currentPlayer'])} to move: [QqRr]> ';
      }
    } else {
      if (winner != null) {
        print('Game over: ${xop(winner)} won!');
      } else if (isDraw) {
        print ('Game over: draw');
      } else {
        print('Game over: $gameOver');
      }
      prompt = 'Return to lobby or Quit? [QqRr]> ';
    }
    stdout.write(prompt);
  });
  client.start();
  try {
    while (true) {
      int input = await nextChar();
      if (validMoves.contains(input - digit0)) {
        client.makeMove('clickCell', [ input - digit0 - 1]);
        prompt = '';
        continue;
      }
      stdout.write('bad input: ');
      stdout.writeCharCode(input);
      stdout.writeln();
      stdout.write(prompt);
    }
  } finally {
    client.leaveGame();
  }
}