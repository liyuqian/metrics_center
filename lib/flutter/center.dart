import 'dart:convert';

import 'package:gcloud/db.dart';
import 'package:gcloud/src/datastore_impl.dart';
import 'package:googleapis_auth/auth.dart';
import 'package:googleapis_auth/auth_io.dart';

import '../base.dart';
import '../flutter/models.dart';
import '../gcslock.dart';

class DatastoreAdaptor {
  /// The projectId will be inferred from the credentials json.
  static Future<DatastoreAdaptor> makeFromCredentialsJson(
      Map<String, dynamic> json) async {
    final client = await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(json), DatastoreImpl.SCOPES);
    final projectId = json['project_id'];
    return DatastoreAdaptor._(
        DatastoreDB(DatastoreImpl(client, projectId)), projectId);
  }

  final String projectId;
  final DatastoreDB db;

  DatastoreAdaptor._(this.db, this.projectId);
}

class FlutterDestination extends MetricsDestination {
  static Future<FlutterDestination> makeFromCredentialsJson(
      Map<String, dynamic> json) async {
    final adaptor = await DatastoreAdaptor.makeFromCredentialsJson(json);
    return FlutterDestination._(adaptor);
  }

  @override
  String get id => kFlutterCenterId;

  @override
  Future<void> update(List<Point> points) async {
    // TODO make a transaction so we'll have all points commited.
    final List<FlutterCenterPoint> flutterCenterPoints =
        points.map((Point p) => FlutterCenterPoint(from: p)).toList();
    await _adaptor.db.commit(inserts: flutterCenterPoints);
  }

  FlutterDestination._(this._adaptor);

  final DatastoreAdaptor _adaptor;
}

// TODO(liyuqian): issue 1. support batching so we won't run out of memory
// TODO(liyuqian): issue 2. integrate info/error logging
// if the list is too large.
class FlutterCenter extends MetricsCenter {
  @override
  String get id => kFlutterCenterId;

  @override
  Future<List<Point>> getUpdatesAfter(DateTime timestamp) async {
    List<Point> result;
    await _lock.protectedRun(() async {
      result = await _getPointsWithinLock(timestamp);
    });
    return result;
  }

  /// 1. Pull data from other sources.
  /// 2. Acquire the global lock (in terms of planet earth) for exclusive
  ///    single-threaded execution below. This ensures that our sourceTime
  ///    timestamp is increasing.
  /// 3. Mark rows with NULL sourceTime with the current time.
  /// 4. Push data from this center to other destinations.
  /// 5. Release the global lock.
  ///
  /// Note that _updateSourceTime triggers an UPDATE request, which is capped by
  /// BigQuery at 1000 times per day per table. So we won't run this synchronize
  /// too often. The current synchronize frequency is once per 30 minutes, or 48
  /// times a day.
  Future<void> synchronize() async {
    await Future.wait(otherSources.map(pullFromSource));
    await _lock.protectedRun(() async {
      await _updateSourceTime();
      await Future.wait(otherDestinations.map(pushToDestination));
    });
  }

  @override
  Future<void> update(List<Point> points) async {
    await _internalDst.update(points);
  }

  static Future<FlutterCenter> makeFromCredentialsJson(
      Map<String, dynamic> json) async {
    final adaptor = await DatastoreAdaptor.makeFromCredentialsJson(json);
    return FlutterCenter._(adaptor);
  }

  Future<void> _updateSourceTime() async {
    final setTime = DateTime.now();

    final Query query = _adaptor.db.query<FlutterCenterPoint>();
    query.filter('$kSourceTimeMicrosName =', null);
    List<FlutterCenterPoint> points = await query.run().toList();
    for (FlutterCenterPoint p in points) {
      p.sourceTimeMicros = setTime.microsecondsSinceEpoch;
    }
    await _adaptor.db.commit(inserts: points);

    // TODO(liyuqian): check if setTime is less than or equal to the largest
    // sourceTime in the table. If so, increment setTime.
  }

  Future<List<Point>> _getPointsWithinLock(DateTime timestamp) async {
    final Query query = _adaptor.db.query<FlutterCenterPoint>();
    query.filter('$kSourceTimeMicrosName >', timestamp.microsecondsSinceEpoch);
    List<FlutterCenterPoint> rawPoints = await query.run().toList();
    List<Point> points = [];
    for (FlutterCenterPoint rawPoint in rawPoints) {
      final Map<String, String> tags = {};
      for (String singleTag in rawPoint.tags) {
        final Map<String, dynamic> decoded = jsonDecode(singleTag);
        assert(decoded.length == 1);
        tags.addAll(decoded.cast<String, String>());
      }
      points.add(Point(
        rawPoint.value,
        tags,
        rawPoint.originId,
        DateTime.fromMicrosecondsSinceEpoch(rawPoint.sourceTimeMicros),
      ));
    }
    return points;
  }

  // TODO also construct with src and dst list
  FlutterCenter._(this._adaptor)
      : _internalDst = FlutterDestination._(_adaptor);

  final FlutterDestination _internalDst;

  final DatastoreAdaptor _adaptor;
  final GcsLock _lock = GcsLock();
}
