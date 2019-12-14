import 'dart:convert';

import 'package:gcloud/storage.dart';
import 'package:googleapis_auth/auth.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:test/test.dart';

import 'package:metrics_center/src/common.dart';
import 'package:metrics_center/src/skiaperf.dart';

import 'utility.dart';

class MockSkiaPerfGcsAdaptor implements SkiaPerfGcsAdaptor {
  @override
  Future<List<SkiaPerfPoint>> readPoints(String objectName) async {
    return _storage[objectName] ?? [];
  }

  @override
  Future<void> writePoints(String objectName, List<SkiaPerfPoint> points) async {
    _storage[objectName] = points.toList();
  }

  // Map from the object name to the list of SkiaPoint that mocks the GCS.
  Map<String, List<SkiaPerfPoint>> _storage = {};
}

@Timeout(Duration(seconds: 3600))
void main() {
  const double value1 = 1.0;
  const double value2 = 2.0;
  const double value3 = 3.0;

  const String frameworkRevision1 = '9011cece2595447eea5dd91adaa241c1c9ef9a33';
  const String frameworkRevision2 = '372fe290e4d4f3f97cbf02a57d235771a9412f10';
  const String name1 = 'analyzer_benchmark.flutter_repo_batch_maximum';
  const String name2 = 'analyzer_benchmark.flutter_repo_watch_maximum';

  const String engineRevision1 = '617938024315e205f26ed72ff0f0647775fa6a71';

  const String testBucketName = 'personal-test-211504-test';

  final cocoonPointRev1Name1 = MetricPoint(
    value1,
    <String, dynamic>{
      kGithubRepoKey: kFlutterFrameworkRepo,
      kGitRevisionKey: frameworkRevision1,
      kTaskNameKey: 'analyzer_benchmark',
      kNameKey: name1,
      kUnitKey: 's',
    },
    kCocoonId,
  );

  final cocoonPointRev1Name2 = MetricPoint(
    value2,
    <String, dynamic>{
      kGithubRepoKey: kFlutterFrameworkRepo,
      kGitRevisionKey: frameworkRevision1,
      kTaskNameKey: 'analyzer_benchmark',
      kNameKey: name2,
      kUnitKey: 's',
    },
    kCocoonId,
  );

  final cocoonPointRev2Name1 = MetricPoint(
    value3,
    <String, dynamic>{
      kGithubRepoKey: kFlutterFrameworkRepo,
      kGitRevisionKey: frameworkRevision2,
      kTaskNameKey: 'analyzer_benchmark',
      kNameKey: name1,
      kUnitKey: 's',
    },
    kCocoonId,
  );

  test('Invalid points convert to null SkiaPoint', () {
    final noGithubRepoPoint = MetricPoint(
      value1,
      <String, dynamic>{
        kGitRevisionKey: frameworkRevision1,
      },
      kCocoonId,
    );

    final noGitRevisionPoint = MetricPoint(
      value1,
      <String, dynamic>{
        kGithubRepoKey: kFlutterFrameworkRepo,
      },
      kCocoonId,
    );

    expect(SkiaPerfPoint.fromPoint(noGithubRepoPoint), isNull);
    expect(SkiaPerfPoint.fromPoint(noGitRevisionPoint), isNull);
  });

  test('Correctly convert a base point from cocoon to SkiaPoint', () {
    final skiaPoint1 = SkiaPerfPoint.fromPoint(cocoonPointRev1Name1);
    expect(skiaPoint1, isNotNull);
    expect(skiaPoint1.originId, equals(kCocoonId));
    expect(skiaPoint1.name, equals(name1));
    expect(skiaPoint1.value, equals(cocoonPointRev1Name1.value));

    expect(skiaPoint1.sourceTime, isNull); // Not inserted yet
    expect(skiaPoint1.jsonUrl, isNull); // Not inserted yet
  });

  test('SkiaPoints correctly encode into Skia perf json format', () {
    final p1 = SkiaPerfPoint.fromPoint(cocoonPointRev1Name1);
    final p2 = SkiaPerfPoint.fromPoint(cocoonPointRev1Name2);

    final JsonEncoder encoder = JsonEncoder.withIndent('  ');
    expect(encoder.convert(SkiaPerfPoint.toSkiaPerfJson(<SkiaPerfPoint>[p1, p2])),
        equals('''
{
  "gitHash": "9011cece2595447eea5dd91adaa241c1c9ef9a33",
  "results": {
    "analyzer_benchmark.flutter_repo_batch_maximum": {
      "value": 1.0,
      "options": {
        "name": "analyzer_benchmark.flutter_repo_batch_maximum",
        "taskName": "analyzer_benchmark",
        "unit": "s",
        "originId": "cocoon"
      }
    },
    "analyzer_benchmark.flutter_repo_watch_maximum": {
      "value": 2.0,
      "options": {
        "name": "analyzer_benchmark.flutter_repo_watch_maximum",
        "taskName": "analyzer_benchmark",
        "unit": "s",
        "originId": "cocoon"
      }
    }
  }
}'''));
  });

  void _expectSetMatch<T>(Iterable<T> actual, Iterable<T> expected) {
    expect(Set<T>.from(actual), equals(Set<T>.from(expected)));
  }

  test('SkiaPerfDestination correctly updates points', () async {
    final mockGcs = MockSkiaPerfGcsAdaptor();
    final dst = SkiaPerfDestination(mockGcs);
    await dst.update(<MetricPoint>[cocoonPointRev1Name1]);
    await dst.update(<MetricPoint>[cocoonPointRev1Name2]);
    List<SkiaPerfPoint> points = await mockGcs.readPoints(
        await SkiaPerfGcsAdaptor.comptueObjectName(
            kFlutterFrameworkRepo, frameworkRevision1));
    expect(points.length, equals(2));
    _expectSetMatch<String>(
        points.map((SkiaPerfPoint p) => p.originId), [kCocoonId, kCocoonId]);
    _expectSetMatch(points.map((SkiaPerfPoint p) => p.name), [name1, name2]);
    _expectSetMatch(points.map((SkiaPerfPoint p) => p.value), [value1, value2]);

    await dst.update(<MetricPoint>[cocoonPointRev1Name1, cocoonPointRev2Name1]);
    points = await mockGcs.readPoints(
        await SkiaPerfGcsAdaptor.comptueObjectName(
            kFlutterFrameworkRepo, frameworkRevision2));
    expect(points.length, equals(1));
    expect(points[0].gitHash, equals(frameworkRevision2));
    expect(points[0].value, equals(value3));
  });

  test('SkiaPerfGcsAdaptor computes name correctly', () async {
    expect(
      await SkiaPerfGcsAdaptor.comptueObjectName(
          kFlutterFrameworkRepo, frameworkRevision1),
      equals('flutter-flutter/2019/12/4/$frameworkRevision1/values.json'),
    );
    expect(
      await SkiaPerfGcsAdaptor.comptueObjectName(
          kFlutterEngineRepo, engineRevision1),
      equals('flutter-engine/2019/12/3/$engineRevision1/values.json'),
    );
  });

  test('SkiaPerfGcsAdaptor passes end-to-end test with Google Cloud Storage',
      () async {
    final Map<String, dynamic> credentialsJson = getGcpCredentialsJson();
    final credentials = ServiceAccountCredentials.fromJson(credentialsJson);

    final client = await clientViaServiceAccount(credentials, Storage.SCOPES);
    final storage = Storage(client, credentialsJson['project_id']);

    expect(await storage.bucketExists(testBucketName), isTrue);

    final Bucket testBucket = storage.bucket(testBucketName);
    final skiaPerfGcs = SkiaPerfGcsAdaptor(testBucket);

    final String testObjectName = await SkiaPerfGcsAdaptor.comptueObjectName(
        kFlutterFrameworkRepo, frameworkRevision1);

    await skiaPerfGcs.writePoints(testObjectName, <SkiaPerfPoint>[
      SkiaPerfPoint.fromPoint(cocoonPointRev1Name1),
      SkiaPerfPoint.fromPoint(cocoonPointRev1Name2),
    ]);

    final List<SkiaPerfPoint> points = await skiaPerfGcs.readPoints(testObjectName);
    expect(points.length, equals(2));
    _expectSetMatch<String>(
        points.map((SkiaPerfPoint p) => p.originId), [kCocoonId, kCocoonId]);
    _expectSetMatch(points.map((SkiaPerfPoint p) => p.name), [name1, name2]);
    _expectSetMatch(points.map((SkiaPerfPoint p) => p.value), [value1, value2]);
    _expectSetMatch(
        points.map((SkiaPerfPoint p) => p.githubRepo), [kFlutterFrameworkRepo]);
    _expectSetMatch(
        points.map((SkiaPerfPoint p) => p.gitHash), [frameworkRevision1]);
    for (int i = 0; i < 2; i += 1) {
      expect(points[0].jsonUrl, startsWith('https://'));
      expect(points[0].sourceTime, isNotNull);
    }
  });
}
