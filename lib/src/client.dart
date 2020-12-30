/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

import './game.dart';
import './lobby.dart';

class Client<G extends Game> {
  Client({
    required this.lobby,
    required this.game,
    required this.playerID,
    required this.credentials,
  });

  final Lobby lobby;
  final G game;
  final String playerID;
  final String credentials;

  Future<void> leaveGame() async {
    await lobby.leaveGame(this);
  }
}
