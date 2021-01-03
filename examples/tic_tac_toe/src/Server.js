/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

const { Server } = require('boardgame.io/server');
const { TicTacToe } = require('./Game');

const server = Server({ games: [TicTacToe] });

server.run(8000);
