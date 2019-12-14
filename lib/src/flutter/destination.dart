import 'package:gcloud/db.dart';
import 'package:metrics_center/src/common.dart';

import 'package:metrics_center/src/flutter/common.dart';

/// The internal implementation [MetricDestination] of [FlutterCenter]
class FlutterDestination extends MetricDestination {
  FlutterDestination(this._db);

  static Future<FlutterDestination> makeFromCredentialsJson(
      Map<String, dynamic> json) async {
    return FlutterDestination(await datastoreFromCredentialsJson(json));
  }

  @override
  String get id => kFlutterCenterId;

  @override
  Future<void> update(List<MetricPoint> points) async {
    final List<MetricPointModel> flutterCenterPoints =
        points.map((MetricPoint p) => MetricPointModel(from: p)).toList();
    await _db.withTransaction((Transaction tx) async {
      tx.queueMutations(inserts: flutterCenterPoints);
      await tx.commit();
    });
  }

  final DatastoreDB _db;
}

// TODO Convenience class FlutterEngineMetricPoint and FlutterFrameworkMetricPoint
