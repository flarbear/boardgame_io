/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

import 'dart:async';

import 'package:boardgame_io/boardgame.dart';
import 'package:flutter/material.dart';

const String _pref_prefix = 'boardgame.io:';

const String _defaultPlayerNameKey = '${_pref_prefix}player-name';

Uri getDefaultLobbyBase([int defaultPort = 8000]) {
  if (Uri.base.scheme == 'file') {
    return Uri.parse('http://localhost:$defaultPort/');
  }
  return Uri.base;
}

abstract class GameOption<T> extends ValueNotifier<T> {
  GameOption(this.setupDataName, T defaultValue) : super(defaultValue);

  final String setupDataName;
  TableRow get widget;
}

typedef String IntOptionLabeler(int i);

abstract class IntGameOption extends GameOption<int> {
  static IntOptionLabeler countLabeler(String? itemName) =>
      (itemName == null)
          ? defaultLabeler
          : (int n) => (n == 1) ? '1 $itemName' : '$n ${itemName}s';

  static String defaultLabeler(int i) => i.toString();

  IntGameOption({
    required String setupDataName,
    String? prompt,
    String? itemName,
    IntOptionLabeler? labeler,
    required int defaultValue,
  })
      : assert(labeler == null || itemName == null),
        prompt = prompt ?? setupDataName,
        labeler = labeler ?? countLabeler(itemName),
        super(setupDataName, defaultValue);

  final String prompt;
  Iterable<int> get values;
  final IntOptionLabeler labeler;

  TableRow get widget => TableRow(
    children: <Widget>[
      Text(prompt, textAlign: TextAlign.end),
      SizedBox(width: 5),
      ValueListenableBuilder<int>(
        valueListenable: this,
        builder: (context, value, child) => DropdownButton<int>(
          value: value,
          onChanged: (newValue) => this.value = newValue!,
          items: <DropdownMenuItem<int>>[
            for (int i in values)
              DropdownMenuItem<int>(
                child: Text(labeler(i)),
                value: i,
              ),
          ],
        ),
      ),
    ],
  );
}

class IntListGameOption extends IntGameOption {
  IntListGameOption({
    required String setupDataName,
    String? prompt,
    required this.values,
    String? itemName,
    IntOptionLabeler? labeler,
    int defaultIndex = 0,
  }) : super(
    setupDataName: setupDataName,
    prompt: prompt,
    itemName: itemName,
    labeler: labeler,
    defaultValue: values[defaultIndex],
  );

  final List<int> values;
}

class IntRangeGameOption extends IntGameOption {
  IntRangeGameOption({
    required String setupDataName,
    String? prompt,
    required this.minValue,
    required this.maxValue,
    String? itemName,
    IntOptionLabeler? labeler,
    int? defaultValue,
  })
      : assert(defaultValue == null || (defaultValue >= minValue && defaultValue <= maxValue)),
        super(
          setupDataName: setupDataName,
          prompt: prompt,
          itemName: itemName,
          labeler: labeler,
          defaultValue: defaultValue ?? minValue,
        );

  final int minValue;
  final int maxValue;
  Iterable<int> get values => Iterable<int>.generate(maxValue + 1).skip(minValue);
}

class PlayerCountOption extends IntRangeGameOption {
  PlayerCountOption(int minPlayers, int maxPlayers, [ int? defaultNumber ]) : super(
    setupDataName: '',
    prompt: 'Number of Players',
    minValue: minPlayers,
    maxValue: maxPlayers,
    itemName: 'Player',
    defaultValue: defaultNumber,
  );
}

class GameProperties {
  GameProperties({
    required this.protocolName,
    String? displayName,
    required this.playerCountOption,
    this.setupOptions = const <GameOption>[],
  })
      : this.displayName = displayName ?? protocolName;

  final String protocolName;
  final String displayName;
  final GameOption<int> playerCountOption;
  final List<GameOption> setupOptions;
}

class LobbyScreen extends StatelessWidget {
  LobbyScreen({
    required this.siteName,
    required this.lobby,
    required this.supportedGames,
    String playerNamePreferencesKey = _defaultPlayerNameKey,
  });

  final String siteName;
  final Lobby lobby;

  final List<GameProperties> supportedGames;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$siteName Lobby'),
        actions: [
          LobbyPlayerName.forLobby(lobby),
        ],
      ),
      body: Center(
        child: LobbyPage(
          lobby: lobby,
          supportedGames: supportedGames,
        ),
      ),
    );
  }
}

class LobbyPlayerName extends StatefulWidget {
  LobbyPlayerName.forLobby(this.lobby)
      : client = null;

  LobbyPlayerName.forClient(Client client)
      : client = client,
        lobby = client.lobby;

  final Client? client;
  final Lobby lobby;

  @override
  State createState() => _LobbyPlayerNameState();
}

class _LobbyPlayerNameState extends State<LobbyPlayerName> {
  late TextEditingController _controller;

  @override
  void initState() {
    print('lobby name widget init');
    super.initState();
    _controller = TextEditingController(text: widget.lobby.playerName);
    widget.lobby.addPlayerNameListener(_updateNameFromLobby);
  }

  @override
  void dispose() {
    print('lobby name widget dispose');
    widget.lobby.removePlayerNameListener(_updateNameFromLobby);
    _controller.dispose();
    super.dispose();
  }

  void _updateNameFromLobby(String newName) {
    _controller.text = newName;
  }

  void _updateNameFromUser(String newName) async {
    if (widget.client == null) {
      widget.lobby.playerName = newName;
    } else {
      await widget.client?.updateName(newName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 10.0),
      width: 250,
      child: TextField(
        controller: _controller,
        maxLength: 30,
        decoration: InputDecoration(
          labelText: 'Player name',
          contentPadding: EdgeInsets.only(top: 10),
          border: UnderlineInputBorder(),
          focusedBorder: UnderlineInputBorder(),
          counter: Offstage(),
        ),
        onSubmitted: (value) => _updateNameFromUser(value),
      ),
    );
  }
}

class LobbyPage extends StatefulWidget {
  LobbyPage({
    required this.lobby,
    required this.supportedGames,
  });

  final Lobby lobby;
  final List<GameProperties> supportedGames;

  @override
  State createState() => LobbyPageState();
}

class LobbyPageState extends State<LobbyPage> {
  List<GameProperties>? _availableGames;
  GameProperties? _chosenGame;

  Timer? _matchTimer;
  List<MatchData>? _allMatches;

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  @override
  void didUpdateWidget(LobbyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _allMatches = null;
    _chosenGame = null;
    _availableGames = null;
    _matchTimer?.cancel();
    _matchTimer = null;
    _loadGames();
  }

  @override
  void dispose() {
    _matchTimer?.cancel();
    _matchTimer = null;
    super.dispose();
  }

  void _loadGames() async {
    Set<String> serverGames = (await widget.lobby.listGames()).toSet();
    List<GameProperties> allGames = widget.supportedGames
        .where((game) => serverGames.contains(game.protocolName))
        .toList();
    setState(() {
      _availableGames = allGames;
    });
    if (allGames.length == 1) {
      _pickedGame(allGames.first);
    }
  }

  void _pickedGame(GameProperties game) {
    setState(() {
      _chosenGame = game;
    });
    _loadMatches();
  }

  void _loadMatches() async {
    List<MatchData> matches = await widget.lobby.listMatches(_chosenGame!.protocolName, force: true);
    setState(() {
      _allMatches = matches.where((match) => match.canJoin).toList();
      if (_matchTimer == null) {
        _matchTimer = Timer.periodic(Duration(seconds: 5), (timer) { _loadMatches(); });
      }
    });
  }

  void _joinMatch(BuildContext context, MatchData match, String playerID) async {
    Client client = await widget.lobby.joinMatch(match.toGame(), playerID);
    Navigator.pushNamed(context, '/play', arguments: client);
  }

  void _createMatch(BuildContext context) async {
    GameProperties props = _chosenGame!;
    GameDescription desc = GameDescription(props.protocolName, props.playerCountOption.value, setupData: {
      for (GameOption option in props.setupOptions)
        option.setupDataName: option.value,
    });
    MatchData match = await widget.lobby.createMatch(desc);
    _joinMatch(context, match, match.players[0].id);
  }

  @override
  Widget build(BuildContext context) {
    final availableGames = _availableGames;
    if (availableGames == null) {
      return Center(child: Text('Loading list of games'));
    }
    final chosenGame = _chosenGame;
    if (chosenGame == null) {
      if (availableGames.length == 0) {
        return Center(child: Text('No supported games on game server.'));
      }
      return Center(
        child: DropdownButton<GameProperties>(
          onChanged: (game) => _pickedGame(game!),
          items: availableGames
              .map((game) => DropdownMenuItem(child: Text(game.displayName), value: game,))
              .toList(),
        ),
      );
    }
    final allMatches = _allMatches;
    if (allMatches == null) {
      return Center(child: Text('Loading list of matches'));
    }
    return Center(
      child: Column(
        children: <Widget>[
          SizedBox(height: 20.0),
          if (allMatches.isNotEmpty)
            Text('Choose a seat in an existing match:'),
          ...allMatches.map((match) {
            return Card(
              child: Padding(
                padding: EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Text('${match.gameName} Match Created: ${match.createdAt}'),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('Seats: '),
                        ...match.players.map((player) {
                          return Padding(
                            padding: EdgeInsets.all(5.0),
                            child: ElevatedButton(
                              onPressed: player.isSeated ? null : () => _joinMatch(context, match, player.id),
                              child: Text(player.seatedName ?? 'Open Seat'),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          SizedBox(height: 20.0),
          allMatches.isEmpty ? Text('Create a match:') : Text('Or, create a new match:'),
          Card(
            child: Padding(
              padding: EdgeInsets.all(10.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Table(
                    defaultColumnWidth: IntrinsicColumnWidth(),
                    defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <TableRow>[
                      chosenGame.playerCountOption.widget,
                      for (final option in chosenGame.setupOptions)
                        option.widget,
                    ],
                  ),
                  SizedBox(width: 20.0),
                  ElevatedButton(
                    onPressed: () => _createMatch(context),
                    child: Text('Create New Game'),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 20.0),
          ElevatedButton(
            onPressed: () => _loadMatches(),
            child: Text('Refresh list of matches'),
          ),
        ],
      ),
    );
  }
}
