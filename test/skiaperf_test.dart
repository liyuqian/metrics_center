import 'dart:convert';

import 'package:test/test.dart';

import '../lib/base.dart';
import '../lib/skiaperf.dart';

class MockSkiaPerfGcsAdaptor implements SkiaPerfGcsAdaptor {
  @override
  String comptueObjectName(String repo, String revision) {
    return '$repo/$revision';
  }

  @override
  Future<List<SkiaPoint>> readPoints(String objectName) async {
    return _storage[objectName] ?? [];
  }

  @override
  Future<void> writePoints(
      String objectName, Iterable<SkiaPoint> points) async {
    _storage[objectName] = points.toList();
  }

  // Map from the object name to the list of SkiaPoint that mocks the GCS.
  Map<String, List<SkiaPoint>> _storage = {};
}

void main() {
  const double value1 = 1.0;
  const double value2 = 2.0;
  const double value3 = 3.0;
  const int dummyTimestamp = 0;

  const String flutterRepo = 'https://github.com/flutter/flutter';
  const String revision1 = 'fe4a4029a080bc955e9588d05a6cd9eb490845d4';
  const String revision2 = '372fe290e4d4f3f97cbf02a57d235771a9412f10';
  const String name1 = 'analyzer_benchmark.flutter_repo_batch_maximum';
  const String name2 = 'analyzer_benchmark.flutter_repo_watch_maximum';

  final cocoonPointRev1Name1 = BasePoint(
    value1,
    <String, dynamic>{
      kGitRepoKey: flutterRepo,
      kGitRevisionKey: revision1,
      kTaskNameKey: 'analyzer_benchmark',
      kNameKey: name1,
      kUnitKey: 's',
    },
    kCocoonId,
    dummyTimestamp,
  );

  final cocoonPointRev1Name2 = BasePoint(
    value2,
    <String, dynamic>{
      kGitRepoKey: flutterRepo,
      kGitRevisionKey: revision1,
      kTaskNameKey: 'analyzer_benchmark',
      kNameKey: name2,
      kUnitKey: 's',
    },
    kCocoonId,
    dummyTimestamp,
  );

  final cocoonPointRev2Name1 = BasePoint(
    value3,
    <String, dynamic>{
      kGitRepoKey: flutterRepo,
      kGitRevisionKey: revision2,
      kTaskNameKey: 'analyzer_benchmark',
      kNameKey: name1,
      kUnitKey: 's',
    },
    kCocoonId,
    dummyTimestamp,
  );

  test('Invalid points convert to null', () {
    final noGitRepoPoint = BasePoint(
      value1,
      <String, dynamic>{
        kGitRevisionKey: revision1,
      },
      kCocoonId,
      dummyTimestamp,
    );

    final noGitRevisionPoint = BasePoint(
      value1,
      <String, dynamic>{
        kGitRepoKey: flutterRepo,
      },
      kCocoonId,
      dummyTimestamp,
    );

    expect(SkiaPoint.fromPoint(noGitRepoPoint), isNull);
    expect(SkiaPoint.fromPoint(noGitRevisionPoint), isNull);
  });

  test('Correctly convert a sample base point from Cocoon', () {
    final skiaPoint = SkiaPoint.fromPoint(cocoonPointRev1Name1);
    expect(skiaPoint, isNotNull);
    expect(skiaPoint.sourceId, equals(kCocoonId));
    expect(skiaPoint.name, equals(name1));
    expect(skiaPoint.value, equals(cocoonPointRev1Name1.value));
    expect(skiaPoint.updateTimeNanos, isNull); // Not inserted yet
    expect(skiaPoint.jsonUrl, isNull); // Not inserted yet

    final JsonEncoder encoder = new JsonEncoder.withIndent('  ');

    expect(encoder.convert(skiaPoint.toSkiaPerfJson()), equals('''
{
  "gitHash": "fe4a4029a080bc955e9588d05a6cd9eb490845d4",
  "results": {
    "analyzer_benchmark.flutter_repo_batch_maximum": {
      "value": 1.0,
      "options": {
        "gitRepo": "https://github.com/flutter/flutter",
        "name": "analyzer_benchmark.flutter_repo_batch_maximum",
        "sourceId": "cocoon",
        "taskName": "analyzer_benchmark",
        "unit": "s"
      }
    }
  }
}'''));
  });

  void _expectSetMatch<T>(Iterable<T> actual, Iterable<T> expected) {
    expect(Set<T>.from(actual), equals(Set<T>.from(expected)));
  }

  test('SkiaPerfDestination correctly update points', () async {
    final mockGcs = MockSkiaPerfGcsAdaptor();
    final dest = SkiaPerfDestination(mockGcs);
    await dest.update(<BasePoint>[cocoonPointRev1Name1]);
    await dest.update(<BasePoint>[cocoonPointRev1Name2]);
    List<SkiaPoint> points = await mockGcs
        .readPoints(mockGcs.comptueObjectName(flutterRepo, revision1));
    expect(points.length, equals(2));
    _expectSetMatch<String>(
        points.map((SkiaPoint p) => p.sourceId), [kCocoonId, kCocoonId]);
    _expectSetMatch(points.map((SkiaPoint p) => p.name), [name1, name2]);
    _expectSetMatch(points.map((SkiaPoint p) => p.value), [value1, value2]);

    await dest.update(<BasePoint>[cocoonPointRev1Name1, cocoonPointRev2Name1]);
    points = await mockGcs.readPoints(mockGcs.comptueObjectName(flutterRepo, revision2));
    expect(points.length, equals(1));
    expect(points[0].gitHash, equals(revision2));
    expect(points[0].value, equals(value3));
  });
}
