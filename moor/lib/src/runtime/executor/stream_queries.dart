import 'dart:async';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:moor/src/utils/start_with_value_transformer.dart';

const _listEquality = ListEquality<dynamic>();

/// Representation of a select statement that knows from which tables the
/// statement is reading its data and how to execute the query.
class QueryStreamFetcher<T> {
  /// The set of tables this query reads from. If any of these tables changes,
  /// the stream must fetch its data again.
  final Set<TableInfo> readsFrom;

  /// Key that can be used to check whether two fetchers will yield the same
  /// result when operating on the same data.
  final StreamKey key;

  /// Function that asynchronously fetches the latest set of data.
  final Future<T> Function() fetchData;

  QueryStreamFetcher(
      {@required this.readsFrom, this.key, @required this.fetchData});
}

/// Key that uniquely identifies a select statement. If two keys created from
/// two select statements are equal, the statements are equal as well.
///
/// As two equal statements always yield the same result when operating on the
/// same data, this can make streams more efficient as we can return the same
/// stream for two equivalent queries.
class StreamKey {
  final String sql;
  final List<dynamic> variables;

  /// Used to differentiate between custom streams, which return a [QueryRow],
  /// and regular streams, which return an instance of a generated data class.
  final Type returnType;

  StreamKey(this.sql, this.variables, this.returnType);

  @override
  int get hashCode {
    return (sql.hashCode * 31 + _listEquality.hash(variables)) * 31 +
        returnType.hashCode;
  }

  @override
  bool operator ==(other) {
    return identical(this, other) ||
        (other is StreamKey &&
            other.sql == sql &&
            _listEquality.equals(other.variables, variables) &&
            other.returnType == returnType);
  }
}

/// Keeps track of active streams created from [SimpleSelectStatement]s and updates
/// them when needed.
class StreamQueryStore {
  final List<QueryStream> _activeStreamsWithoutKey = [];
  final Map<StreamKey, QueryStream> _activeKeyStreams = {};
  final StreamController<Set<String>> _tableChangeNotifier =
      StreamController.broadcast();

  StreamQueryStore();

  /// Creates a new stream from the select statement.
  Stream<T> registerStream<T>(QueryStreamFetcher<T> fetcher) {
    final key = fetcher.key;
    final readsFrom = fetcher.readsFrom.map((t) => t.actualTableName).toSet();
    final sourceTables = _tableChangeNotifier.stream
        .where((tables) => tables.intersection(readsFrom).isNotEmpty);

    if (key == null) {
      final stream = QueryStream(fetcher, this, sourceTables);
      _activeStreamsWithoutKey.add(stream);
      return stream.stream;
    } else {
      final stream = _activeKeyStreams.putIfAbsent(key, () {
        return QueryStream<T>(fetcher, this, sourceTables);
      });

      return (stream as QueryStream<T>).stream;
    }
  }

  /// Handles updates on a given table by re-executing all queries that read
  /// from that table.
  Future<void> handleTableUpdates(Set<TableInfo> tables) async {
    final updatedNames = tables.map((t) => t.actualTableName).toSet();
    _tableChangeNotifier.add(updatedNames);
  }

  void markAsClosed(QueryStream stream) {
    final key = stream._fetcher.key;
    if (key == null) {
      _activeStreamsWithoutKey.remove(stream);
    } else {
      _activeKeyStreams.remove(key);
    }
  }
}

class QueryStream<T> {
  final QueryStreamFetcher<T> _fetcher;
  final StreamQueryStore _store;
  final Stream<Set<String>> _sourceTables;

  StreamController<T> _controller;

  StreamSubscription<void> _tableChangeSub;
  T _lastData;

  Stream<T> get stream {
    _controller ??= StreamController.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );

    return _controller.stream.transform(StartWithValueTransformer(_cachedData));
  }

  QueryStream(this._fetcher, this._store, this._sourceTables);

  /// Called when we have a new listener, makes the stream query behave similar
  /// to an `BehaviorSubject` from rxdart.
  T _cachedData() => _lastData;

  void _onListen() {
    // First listener added.
    // Start listening for table changes and re-run the query.
    _listenToSourceTables();
    _fetchAndEmitData();
  }

  void _onCancel() {
    // todo this removes the stream from the list so that it can be garbage
    // collected. When a stream is never listened to, we have a memory leak as
    // this will never be called. Maybe an Expando (which uses weak references)
    // can save us here?
    _store.markAsClosed(this);

    // Stop listening for table updates
    _tableChangeSub?.cancel();
    _tableChangeSub = null;

    // Even though we've removed from the store and there are no current
    // listeners, someone might still be holding a reference to this QueryStream
    // so don't close the controller.
    // Instead, set the most recent value to null so that new listeners don't
    // get a stale value while waiting for _fetchAndEmitData to return.
    _lastData = null;
  }

  void _listenToSourceTables() {
    _tableChangeSub ??=
      _sourceTables.listen((_) => _fetchAndEmitData());
  }

  Future<void> _fetchAndEmitData() async {
    // We should always have a listener when this is called since we
    // unsubscribe from _sourceTables when there are no more listeners,
    // but _onCancel() just in case to prevent stale data.
    if (!_controller.hasListener) {
      _onCancel();
      return;
    }

    final data = await _fetcher.fetchData();
    _lastData = data;

    if (!_controller.isClosed) {
      _controller.add(data);
    }
  }
}
