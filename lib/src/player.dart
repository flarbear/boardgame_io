/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

/// A player in a game served by a boardgame.io server.
class Player {
  /// Creates a player with, minimally, the indicated protocol-level [id]
  /// and with optional name and connection status for players that are
  /// already seated at the game.
  Player(this.id, { String? name, bool isConnected = false })
      : this._name = name,
        this._isConnected = isConnected;

  /// Creates a [Player] object from the information given in a map
  /// decoded from a JSON encoded boardgame.io network request.
  factory Player.fromJson(Map<String, dynamic> jsonData) {
    return Player(jsonData['id']!.toString(),
      name: jsonData['name'],
      isConnected: jsonData['isConnected'] ?? false,
    );
  }

  /// The (required) player ID.
  final String id;

  String? _name;

  /// The (optional) name of the player seated in this position.
  String? get seatedName => _name;

  /// Returns a name for this seat whether or not there is a player seated.
  ///
  /// This property is primarily used when displaying a game board so that
  /// all seats can have a name associated with them. If the board renderer
  /// is sophisticated enough to render a seat without a player, then the
  /// renderer can use [isSeated] and [seatedName] to optionally indicate
  /// a player name for occupied seats or some other indication for empty seats.
  String get name => _name ?? 'Player $id';

  /// True iff there is a player who has claimed this seat.
  ///
  /// Note that this is not the same as [isConnected] as the latter indicates
  /// whether or not they have an active [Client] managing their participation
  /// in the game. It is possible for a player to claim a seat using the [Lobby]
  /// but not actually have an active [Client], though the intent is that they
  /// should soon connect, otherwise the game may become unplayable with
  /// absent players tying up seats.
  bool get isSeated => _name != null;

  bool _isConnected = false;

  /// True iff there is a player with an active [Client] participating with
  /// this seat.
  ///
  /// Note that this is not the same as [isSeated] as the latter indicates
  /// whether or not someone has claimed the seat using the lobby mechanism.
  /// It is possible for a player to claim a seat using the [Lobby] but not
  /// actually have an active [Client], though the intent is that they
  /// should soon connect, otherwise the game may become unplayable with
  /// absent players tying up seats.
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
    return (other is Player) && id == other.id;
  }
}
