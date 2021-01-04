/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

/// The boardgame_io library provides Dart language bindings for the various
/// client-side aspects of a boardgame.io game.
///
/// These classes provide the support that would typically be used in a
/// boardgame.io `App.js` file to create a client and board rendering front
/// end to play the game. Using these classes one should be able to create
/// a front end entirely in Dart or potentially Flutter.
library boardgame_io;

export 'src/client.dart';
export 'src/game.dart';
export 'src/lobby.dart';
export 'src/player.dart';
