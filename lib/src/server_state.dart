/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

class RefreshableState<T> {
  RefreshableState(this.freshness, this._load)
      : _expiration = DateTime.now().subtract(Duration(days: 1));

  final Duration freshness;

  DateTime _expiration;
  T? _lastReceived;

  bool get _stale => !DateTime.now().isBefore(_expiration);

  T? check() {
    return _stale ? null : _lastReceived;
  }

  Future<T> get({ bool force = false, }) async {
    if (force || _stale) {
      return refresh();
    }
    return _lastReceived!;
  }

  Future<T> refresh() async {
    T newValue = await _load(_lastReceived);
    _lastReceived = newValue;
    _expiration = DateTime.now().add(freshness);
    return newValue;
  }

  Future<T> Function(T? previousValue) _load;
}
