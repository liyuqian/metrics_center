import 'dart:convert';
import 'dart:math';

import 'package:gcloud/db.dart';

import 'package:metrics_center/src/common.dart';
import 'package:metrics_center/src/gcslock.dart';

import 'package:metrics_center/src/flutter/common.dart';

/// The internal implementation [MetricSource] of [FlutterCenter]
class FlutterSource extends MetricSource {
  FlutterSource(this._db);

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
    final Query query = _db.query<MetricPointModel>();
    // TODO(liyuqian): Undo the 300 limit once
    // https://github.com/dart-lang/gcloud/issues/87 is fixed.
    query..filter('$kSourceTimeMicrosName =', null)..limit(300);
    List<MetricPointModel> points = await query.run().toList();

    for (int start = 0; start < points.length; start += kMaxBatchSize) {
      final int end = min(points.length, start + kMaxBatchSize);
      final List<MetricPointModel> batch = points.sublist(start, end);
      final setTime = DateTime.now();
      for (MetricPointModel p in batch) {
        p.sourceTimeMicros = setTime.microsecondsSinceEpoch;
      }
      // It's Ok to not have a transaction here and only have only
      // part of points being updated.
      await _db.commit(inserts: batch);
    }
  }

  Future<List<MetricPoint>> _getPointsWithinLock(DateTime timestamp) async {
    final Query query = _db.query<MetricPointModel>();
    query.filter('$kSourceTimeMicrosName >', timestamp.microsecondsSinceEpoch);
    // TODO(liyuqian): Undo the 300 limit once
    // https://github.com/dart-lang/gcloud/issues/87 is fixed.
    query.limit(300);
    List<MetricPointModel> rawPoints = await query.run().toList();
    List<MetricPoint> points = [];
    for (MetricPointModel rawPoint in rawPoints) {
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

  final DatastoreDB _db;
  final GcsLock _lock = GcsLock();
}
