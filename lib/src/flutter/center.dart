import 'package:gcloud/db.dart';
import 'package:metrics_center/src/common.dart';

import 'package:metrics_center/src/flutter/common.dart';
import 'package:metrics_center/src/flutter/destination.dart';
import 'package:metrics_center/src/flutter/source.dart';
import 'package:metrics_center/src/skiaperf.dart';

import 'package:gcloud/src/datastore_impl.dart';

// TODO(liyuqian): issue 1. support batching so we won't run out of memory if
// the list is too large.
//
// TODO(liyuqian): issue 2. integrate info/error logging
class FlutterCenter {
  /// Call this method periodically to synchronize metric points among mutliple
  /// sources and destinations.
  ///
  /// This method does
  /// 1. Pull data from other sources into this center.
  /// 2. Set sourceTime of the newly added points.
  /// 3. Push data from this center to other destinations.
  /// 4. Write the updated srcUpdateTime and dstUpdateTime into Datastore.
  ///
  /// Returns the total number of points pulled or pushed.
  Future<int> synchronize() async {
    final List<int> pulled =
        await Future.wait(_otherSources.map(_pullFromSource));

    await _flutterSrc.updateSourceTime();

    final List<int> pushed =
        await Future.wait(_otherDestinations.map(_pushToDestination));

    await _writeUpdateTime();

    int sum(int a, int b) => a + b;
    final int totalPulled = pulled.isNotEmpty ? pulled.reduce(sum) : 0;
    final int totalPushed = pushed.isNotEmpty ? pushed.reduce(sum) : 0;
    return totalPulled + totalPushed;
  }

  FlutterCenter(
    DatastoreDB db, {
    FlutterSource flutterSource,
    FlutterDestination flutterDestination,
    List<MetricSource> otherSources,
    List<MetricDestination> otherDestinations,
    Map<String, DateTime> srcUpdateTime,
    Map<String, DateTime> dstUpdateTime,
  })  : _flutterDst = flutterDestination,
        _flutterSrc = flutterSource,
        _otherSources = otherSources,
        _otherDestinations = otherDestinations,
        _srcUpdateTime = srcUpdateTime,
        _dstUpdateTime = dstUpdateTime,
        _db = db {
    _flutterSrc ??= FlutterSource(db);
    _flutterDst ??= FlutterDestination(db);

    _otherSources ??= [];

    _otherDestinations ??= [];

    _srcUpdateTime ??= {};
    _dstUpdateTime ??= {};

    final DateTime kSmallestTime = DateTime.fromMicrosecondsSinceEpoch(0);
    for (MetricSource src in _otherSources) {
      _srcUpdateTime[src.id] ??= kSmallestTime;
    }
    for (MetricDestination dst in _otherDestinations) {
      _dstUpdateTime[dst.id] ??= kSmallestTime;
    }
  }

  static Future<FlutterCenter> makeDefault(Map<String, dynamic> gcpCredentials,
      {bool isTesting = false}) async {
    final db = await datastoreFromCredentialsJson(gcpCredentials);
    final query = db.query<UpdateTimeModel>();
    final List<UpdateTimeModel> models = await query.run().toList();
    final Map<String, DateTime> srcUpdateTime = {};
    final Map<String, DateTime> dstUpdateTime = {};
    for (UpdateTimeModel model in models) {
      final String id = model.id.toString();
      if (id.startsWith(UpdateTimeModel.kSrcPrefix)) {
        srcUpdateTime[UpdateTimeModel.getSrcId(id)] =
            DateTime.fromMicrosecondsSinceEpoch(model.micros);
      } else {
        assert(id.startsWith(UpdateTimeModel.kDstPrefix));
        dstUpdateTime[UpdateTimeModel.getDstId(id)] =
            DateTime.fromMicrosecondsSinceEpoch(model.micros);
      }
    }

    // By default, we use SkiaPerf as our unique other destination. Future
    // sources and destinations should be added here so
    // bin/run_flutter_center.dart would have them.
    final List<MetricDestination> destinations = [
      await SkiaPerfDestination.makeFromGcpCredentials(gcpCredentials,
          isTesting: isTesting),
    ];

    return FlutterCenter(
      db,
      otherDestinations: destinations,
      srcUpdateTime: srcUpdateTime,
      dstUpdateTime: dstUpdateTime,
    );
  }

  /// Take a list of [points] with sorted sourceTime, return a prefix sublist
  /// whose length is no more than [size]. The last element of the returned list
  /// must either be the last element of [points], or have a strictly smaller
  /// sourceTime than the next element in [points].
  ///
  /// This helps [synchronize] to only handle a limited size of points at a time
  /// so it won't trigger some out-of-quota issue.
  ///
  /// If the returned list can ony be empty, an exception may be thrown.
  static List<MetricPoint> limitSize(List<MetricPoint> points, int size) {
    if (points.length <= size) {
      return points;
    }
    for (int i = size; i > 0; i -= 1) {
      if (points[i].sourceTime.microsecondsSinceEpoch >
          points[i - 1].sourceTime.microsecondsSinceEpoch) {
        return points.sublist(0, i);
      }
    }
    throw Exception('Cannot return an nonempty list with the limited size.');
  }

  Future<void> _writeUpdateTime() async {
    final List<UpdateTimeModel> models = [
      ..._srcUpdateTime.entries.map((x) => UpdateTimeModel.src(x.key, x.value)),
      ..._dstUpdateTime.entries.map((x) => UpdateTimeModel.dst(x.key, x.value)),
    ];
    // We won't use transactions as it's Ok to have some writes failed.
    await _db.commit(inserts: models);
  }

  // Returns the number of points pushed
  Future<int> _pushToDestination(MetricDestination destination) async {
    // To dedup, do not send data from that destination. This is important as
    // some destinations are also sources (e.g., [FlutterCenter]).
    List<MetricPoint> points =
        (await _flutterSrc.getUpdatesAfter(_dstUpdateTime[destination.id]))
            .where(
              (p) => p.originId != destination.id,
            )
            .toList();
    if (points.isEmpty) {
      return 0;
    }
    points = limitSize(points, kMaxBatchSize);
    await destination.update(points);
    assert(points.last.sourceTime != null);
    _dstUpdateTime[destination.id] = points.last.sourceTime;
    return points.length;
  }

  // Returns the number of points pulled.
  Future<int> _pullFromSource(MetricSource source) async {
    // To dedup, don't pull any data from other sources. This is important as
    // some sources are also destinations (e.g., [FlutterCenter]), and data from
    // other sources could be pushed there.
    List<MetricPoint> points =
        (await source.getUpdatesAfter(_srcUpdateTime[source.id]))
            .where((p) => p.originId == source.id)
            .toList();
    if (points.isEmpty) {
      return 0;
    }
    points = limitSize(points, kMaxBatchSize);
    await _flutterDst.update(points);
    assert(points.last.sourceTime.microsecondsSinceEpoch >
        _srcUpdateTime[source.id].microsecondsSinceEpoch);
    _srcUpdateTime[source.id] = points.last.sourceTime;
    return points.length;
  }

  // Map from a source id to the largest sourceTime timestamp of any data that
  // this center has pulled from it.
  //
  // The timestamp is generated in the source, and it may have a clock that's
  // not in sync with the [FlutterCenter]'s clock.
  //
  // We only require that the source's clock is strictly increasing between
  // batches: if [getUpdateAfter] already returned a list of data points with
  // the largest [sourceTime] = x, then the later updates must have strictly
  // greater [sourceTime] > x.
  Map<String, DateTime> _srcUpdateTime;

  // Map from a destination id to the largest sourceTime of any data that this
  // center has pushed to it.
  //
  // This timestamp is generated by [FlutterCenter] (a [MetricSource]) so its
  // [sourceTime] is strictly increasing between batches.
  Map<String, DateTime> _dstUpdateTime;

  List<MetricSource> _otherSources;
  List<MetricDestination> _otherDestinations;

  FlutterSource _flutterSrc;
  FlutterDestination _flutterDst;

  final DatastoreDB _db;
}

@Kind(name: 'UpdateTime', idType: IdType.String)
class UpdateTimeModel extends Model {
  @IntProperty(required: true, indexed: false)
  int micros;

  UpdateTimeModel();

  UpdateTimeModel.src(String srcId, DateTime t) {
    id = '$kSrcPrefix$srcId';
    micros = t.microsecondsSinceEpoch;
  }

  UpdateTimeModel.dst(String dstId, DateTime t) {
    id = '$kDstPrefix$dstId';
    micros = t.microsecondsSinceEpoch;
  }

  static const String kSrcPrefix = 'src: ';
  static const String kDstPrefix = 'dst: ';

  static String getSrcId(String fullId) => fullId.substring(kSrcPrefix.length);
  static String getDstId(String fullId) => fullId.substring(kDstPrefix.length);
}
