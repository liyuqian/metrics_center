import 'package:metrics_center/src/common.dart';

import 'package:metrics_center/src/flutter/common.dart';

/// The internal implementation [MetricDestination] of [FlutterCenter]
class FlutterDestination extends MetricDestination {
  FlutterDestination(this._adaptor);

  static Future<FlutterDestination> makeFromCredentialsJson(
      Map<String, dynamic> json) async {
    final adaptor = await DatastoreAdaptor.makeFromCredentialsJson(json);
    return FlutterDestination(adaptor);
  }

  @override
  String get id => kFlutterCenterId;

  @override
  Future<void> update(List<MetricPoint> points) async {
    // TODO make a transaction so we'll have all points commited.
    final List<FlutterCenterPoint> flutterCenterPoints =
        points.map((MetricPoint p) => FlutterCenterPoint(from: p)).toList();
    await _adaptor.db.commit(inserts: flutterCenterPoints);
  }

  final DatastoreAdaptor _adaptor;
}

// TODO Convenience class for FlutterEngineMetricPoint and FlutterFrameworkMetricPoint
