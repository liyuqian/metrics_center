import 'dart:math';

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

  static FlutterDestination makeFromAccessToken(
    String accessToken, [
    String projectId = kDefaultGoogleCloudProjectId,
  ]) {
    return FlutterDestination(datastoreFromAccessToken(accessToken, projectId));
  }

  @override
  String get id => kFlutterCenterId;

  @override
  Future<void> update(List<MetricPoint> points) async {
    final List<MetricPointModel> flutterCenterPoints =
        points.map((MetricPoint p) => MetricPointModel(from: p)).toList();

    for (int start = 0; start < points.length; start += kMaxBatchSize) {
      final int end = min(start + kMaxBatchSize, points.length);
      await _db.withTransaction((Transaction tx) async {
        tx.queueMutations(inserts: flutterCenterPoints.sublist(start, end));
        await tx.commit();
      });
    }
  }

  final DatastoreDB _db;
}

/// Convenient class to capture the benchmarks in the Flutter engine repo.
class FlutterEngineMetricPoint extends MetricPoint {
  FlutterEngineMetricPoint(
    String name,
    double value,
    String gitRevision, {
    Map<String, String> moreTags,
  }) : super(
            value,
            {
              kNameKey: name,
              kGithubRepoKey: kFlutterEngineRepo,
              kGitRevisionKey: gitRevision,
            }..addAll(moreTags ?? {}),
            kFlutterCenterId);
}
