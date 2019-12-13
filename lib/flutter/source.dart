import 'dart:convert';

import 'package:gcloud/db.dart';

import '../common.dart';
import '../gcslock.dart';

import 'common.dart';

/// The internal implementation [MetricSource] of [FlutterCenter]
class FlutterSource extends MetricSource {
  FlutterSource(this._adaptor);

  @override
  String get id => kFlutterCenterId;

  @override
  Future<List<MetricPoint>> getUpdatesAfter(DateTime timestamp) async {
    List<MetricPoint> result;
    await _lock.protectedRun(() async {
      result = await _getPointsWithinLock(timestamp);
    });
    return result;
  }

  /// Lock the source (globally on earth), wait [kTinyDuration], and set
  /// sourceTime to now for the points that have null sourceTime.
  ///
  /// The lock and the tiny wait should ensure the strict monotonicity
  /// required by [MetricSource].
  Future<void> updateSourceTime() async {
    await _lock.protectedRun(() async {
      await Future.delayed(kTinyDuration);
      await _updateSourceTimeWithinLock();
    });
  }

  static const Duration kTinyDuration = Duration(milliseconds: 1);

  Future<void> _updateSourceTimeWithinLock() async {
    final setTime = DateTime.now();

    final Query query = _adaptor.db.query<FlutterCenterPoint>();
    query.filter('$kSourceTimeMicrosName =', null);
    List<FlutterCenterPoint> points = await query.run().toList();
    for (FlutterCenterPoint p in points) {
      p.sourceTimeMicros = setTime.microsecondsSinceEpoch;
    }

    // It's Ok to not have a transaction here and only have only
    // part of points being updated.
    // TODO(liyuqian): add logging for failures.
    await _adaptor.db.commit(inserts: points);
  }

  Future<List<MetricPoint>> _getPointsWithinLock(DateTime timestamp) async {
    final Query query = _adaptor.db.query<FlutterCenterPoint>();
    query.filter('$kSourceTimeMicrosName >', timestamp.microsecondsSinceEpoch);
    List<FlutterCenterPoint> rawPoints = await query.run().toList();
    List<MetricPoint> points = [];
    for (FlutterCenterPoint rawPoint in rawPoints) {
      final Map<String, String> tags = {};
      for (String singleTag in rawPoint.tags) {
        final Map<String, dynamic> decoded = jsonDecode(singleTag);
        assert(decoded.length == 1);
        tags.addAll(decoded.cast<String, String>());
      }
      points.add(MetricPoint(
        rawPoint.value,
        tags,
        rawPoint.originId,
        DateTime.fromMicrosecondsSinceEpoch(rawPoint.sourceTimeMicros),
      ));
    }
    return points;
  }

  final DatastoreAdaptor _adaptor;
  final GcsLock _lock = GcsLock();
}
