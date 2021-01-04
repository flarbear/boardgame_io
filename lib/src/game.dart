/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

/// General description of a game supported by a boardgame.io server
/// that is not associated with a specific match.
///
/// This base class only requires the basic information required by
/// a boardgame.io server for any game. A subclass might include
/// additional information that will be supplied to the server via
/// the setupData protocol.
///
/// This description can be used to create a new match, or it can
/// be associated with an existing match using the [makeGame] method.
class GameDescription {
  GameDescription(this.name, this.numPlayers);

  /// The protocol name for the game instance on the server side.
  final String name;

  /// The number of players allowed in the game.
  final int numPlayers;

  /// Used to associate this [GameDescription] with a specific
  /// match, resulting in a [Game].
  Game makeGame(String matchID) {
    return Game(this, matchID);
  }
}

/// An association of a boardgame.io game description with a
/// specific match ID.
class Game {
  Game(this.description, this.matchID);

  final GameDescription description;
  final String matchID;
}
