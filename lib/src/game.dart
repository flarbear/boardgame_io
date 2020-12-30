/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

class GameDescription {
  GameDescription(this.name, this.numPlayers);

  final String name;
  final int numPlayers;

  Game makeGame(String matchID) {
    return Game(this, matchID);
  }
}

class Game {
  Game(this.description, this.matchID);

  final GameDescription description;
  final String matchID;
}