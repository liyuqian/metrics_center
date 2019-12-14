import 'package:gcloud/db.dart';
import 'package:metrics_center/src/common.dart';

import 'package:metrics_center/src/flutter/common.dart';
import 'package:metrics_center/src/flutter/destination.dart';
import 'package:metrics_center/src/flutter/source.dart';

// TODO(liyuqian): issue 1. support batching so we won't run out of memory
// TODO(liyuqian): issue 2. integrate info/error logging if the list is too
// large.
class FlutterCenter {
  /// Call this method periodically to synchronize metric points among mutliple
  /// sources and destinations.
  ///
  /// This method does
  /// 1. Pull data from other sources into this center.
  /// 2. Set sourceTime of the newly added points.
  /// 3. Push data from this center to other destinations.
  /// 4. Write the updated srcUpdateTime and dstUpdateTime into Datastore.
  Future<void> synchronize() async {
    await Future.wait(_otherSources.map(_pullFromSource));
    await _flutterSrc.updateSourceTime();
    await Future.wait(_otherDestinations.map(_pushToDestination));
    await _writeUpdateTime();
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

    // TODO(liyuqian): add SkiaPerfDestination as a default other destination
    // if the constructor doesn't specify one
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

  static Future<FlutterCenter> makeFromCredentialsJson(
      Map<String, dynamic> json) async {
    final db = await datastoreFromCredentialsJson(json);
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
    return FlutterCenter(db);
  }

  Future<void> _writeUpdateTime() async {
    final List<UpdateTimeModel> models = [
      ..._srcUpdateTime.entries.map((x) => UpdateTimeModel.src(x.key, x.value)),
      ..._dstUpdateTime.entries.map((x) => UpdateTimeModel.dst(x.key, x.value)),
    ];
    // We won't use transactions as it's Ok to have some writes failed.
    await _db.commit(inserts: models);
  }

  Future<void> _pushToDestination(MetricDestination destination) async {
    // To dedup, do not send data from that destination. This is important as
    // some destinations are also sources (e.g., a [MetricsCenter]).
    List<MetricPoint> points =
        (await _flutterSrc.getUpdatesAfter(_dstUpdateTime[destination.id]))
            .where(
              (p) => p.originId != destination.id,
            )
            .toList();
    if (points.isEmpty) {
      return;
    }
    await destination.update(points);
    assert(points.last.sourceTime != null);
    _dstUpdateTime[destination.id] = points.last.sourceTime;
  }

  Future<void> _pullFromSource(MetricSource source) async {
    // To dedup, don't pull any data from other sources. This is important as
    // some sources are also destinations (e.g., [MetricsCenter]), and data from
    // other sources could be pushed there.
    List<MetricPoint> points =
        (await source.getUpdatesAfter(_srcUpdateTime[source.id]))
            .where((p) => p.originId == source.id)
            .toList();
    if (points.isEmpty) {
      return;
    }
    await _flutterDst.update(points);
    assert(points.last.sourceTime.microsecondsSinceEpoch >
        _srcUpdateTime[source.id].microsecondsSinceEpoch);
    _srcUpdateTime[source.id] = points.last.sourceTime;
  }

  // Map from a source id to the largest sourceTime timestamp of any data that
  // this center has pulled from it.
  //
  // The timestamp is generated in the source, and it may have a clock that's
  // not in sync with the [MetricsCenter]'s clock.
  //
  // We only require that the source's clock is strictly increasing between
  // batches: if [getUpdateAfter] already returned a list of data points with
  // the largest [sourceTime] = x, then the later updates must have strictly
  // greater [sourceTime] > x.
  Map<String, DateTime> _srcUpdateTime;

  // Map from a destination id to the largest sourceTime of any data that this
  // center has pushed to it.
  //
  // This timestamp is generated by [MetricsCenter] (a [MetricSource]) so its
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
