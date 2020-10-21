@Timeout(Duration(seconds: 3600))

import 'dart:convert';

import 'package:gcloud/storage.dart';
import 'package:googleapis_auth/auth.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:metrics_center/flutter.dart';
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
  Future<void> writePoints(
      String objectName, List<SkiaPerfPoint> points) async {
    _storage[objectName] = points.toList();
  }

  // Map from the object name to the list of SkiaPoint that mocks the GCS.
  Map<String, List<SkiaPerfPoint>> _storage = {};
}

void main() {
  const double value1 = 1.0;
  const double value2 = 2.0;
  const double value3 = 3.0;

  const String frameworkRevision1 = '9011cece2595447eea5dd91adaa241c1c9ef9a33';
  const String frameworkRevision2 = '372fe290e4d4f3f97cbf02a57d235771a9412f10';
  const String taskName = 'analyzer_benchmark';
  const String metric1 = 'flutter_repo_batch_maximum';
  const String metric2 = 'flutter_repo_watch_maximum';

  const String engineRevision1 = '617938024315e205f26ed72ff0f0647775fa6a71';
  const String engineRevision2 = '5858519139c22484aaff1cf5b26bdf7951259344';

  final cocoonPointRev1Metric1 = MetricPoint(
    value1,
    <String, dynamic>{
      kGithubRepoKey: kFlutterFrameworkRepo,
      kGitRevisionKey: frameworkRevision1,
      kNameKey: taskName,
      kSubResultKey: metric1,
      kUnitKey: 's',
    },
    kCocoonId,
  );

  final cocoonPointRev1Metric2 = MetricPoint(
    value2,
    <String, dynamic>{
      kGithubRepoKey: kFlutterFrameworkRepo,
      kGitRevisionKey: frameworkRevision1,
      kNameKey: taskName,
      kSubResultKey: metric2,
      kUnitKey: 's',
    },
    kCocoonId,
  );

  final cocoonPointRev2Metric1 = MetricPoint(
    value3,
    <String, dynamic>{
      kGithubRepoKey: kFlutterFrameworkRepo,
      kGitRevisionKey: frameworkRevision2,
      kNameKey: taskName,
      kSubResultKey: metric1,
      kUnitKey: 's',
    },
    kCocoonId,
  );

  final cocoonPointBetaRev1Metric1 = MetricPoint(
    value1,
    <String, dynamic>{
      kGithubRepoKey: kFlutterFrameworkRepo,
      kGitRevisionKey: frameworkRevision1,
      kNameKey: 'beta/$taskName',
      kSubResultKey: metric1,
      kUnitKey: 's',
      'branch': 'beta',
    },
    kCocoonId,
  );

  final cocoonPointBetaRev1Metric1BadName = MetricPoint(
    value1,
    <String, dynamic>{
      kGithubRepoKey: kFlutterFrameworkRepo,
      kGitRevisionKey: frameworkRevision1,
      kNameKey: taskName,
      kSubResultKey: metric1,
      kUnitKey: 's',

      // If we only add this 'branch' tag without changing the value of, an
      // exception would be thrown as Skia Perf currently only supports the same
      // set of tags for a pair of kNameKey and kSubResultKey values.
      'branch': 'beta',
    },
    kCocoonId,
  );

  const String engineMetricName = 'BM_PaintRecordInit';
  const String engineRevision = 'ca799fa8b2254d09664b78ee80c43b434788d112';
  const double engineValue1 = 101;
  const double engineValue2 = 102;

  final enginePoint1 = FlutterEngineMetricPoint(
    engineMetricName,
    engineValue1,
    engineRevision,
    moreTags: {
      kSubResultKey: 'cpu_time',
      kUnitKey: 'ns',
      'date': '2019-12-17 15:14:14',
      'num_cpus': '56',
      'mhz_per_cpu': '2594',
      'cpu_scaling_enabled': 'true',
      'library_build_type': 'release',
    },
  );

  final enginePoint2 = FlutterEngineMetricPoint(
    engineMetricName,
    engineValue2,
    engineRevision,
    moreTags: {
      kSubResultKey: 'real_time',
      kUnitKey: 'ns',
      'date': '2019-12-17 15:14:14',
      'num_cpus': '56',
      'mhz_per_cpu': '2594',
      'cpu_scaling_enabled': 'true',
      'library_build_type': 'release',
    },
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
    final skiaPoint1 = SkiaPerfPoint.fromPoint(cocoonPointRev1Metric1);
    expect(skiaPoint1, isNotNull);
    expect(skiaPoint1.originId, equals(kCocoonId));
    expect(skiaPoint1.name, equals(taskName));
    expect(skiaPoint1.subResult, equals(metric1));
    expect(skiaPoint1.value, equals(cocoonPointRev1Metric1.value));

    expect(skiaPoint1.sourceTime, isNull); // Not inserted yet
    expect(skiaPoint1.jsonUrl, isNull); // Not inserted yet
  });

  test('Cocoon points correctly encode into Skia perf json format', () {
    final p1 = SkiaPerfPoint.fromPoint(cocoonPointRev1Metric1);
    final p2 = SkiaPerfPoint.fromPoint(cocoonPointRev1Metric2);
    final p3 = SkiaPerfPoint.fromPoint(cocoonPointBetaRev1Metric1);

    final JsonEncoder encoder = JsonEncoder.withIndent('  ');

    expect(
        encoder.convert(SkiaPerfPoint.toSkiaPerfJson(<SkiaPerfPoint>[p1, p2, p3])),
        equals('''
{
  "gitHash": "9011cece2595447eea5dd91adaa241c1c9ef9a33",
  "results": {
    "analyzer_benchmark": {
      "default": {
        "flutter_repo_batch_maximum": 1.0,
        "options": {
          "unit": "s",
          "originId": "cocoon"
        },
        "flutter_repo_watch_maximum": 2.0
      }
    },
    "beta/analyzer_benchmark": {
      "default": {
        "flutter_repo_batch_maximum": 1.0,
        "options": {
          "branch": "beta",
          "unit": "s",
          "originId": "cocoon"
        }
      }
    }
  }
}'''));
  });

  test('Throws if two SkiaPerfPoints have the same name and subResult keys, '
       'but different options', () {
    final p1 = SkiaPerfPoint.fromPoint(cocoonPointRev1Metric1);
    final p2 = SkiaPerfPoint.fromPoint(cocoonPointBetaRev1Metric1BadName);

    expect(
      () => SkiaPerfPoint.toSkiaPerfJson(<SkiaPerfPoint>[p1, p2]),
      throwsA(anything),
    );
  });

  test('Engine points correctly encode into Skia perf json format', () {
    final JsonEncoder encoder = JsonEncoder.withIndent('  ');
    expect(
      encoder.convert(SkiaPerfPoint.toSkiaPerfJson(<SkiaPerfPoint>[
        SkiaPerfPoint.fromPoint(enginePoint1),
        SkiaPerfPoint.fromPoint(enginePoint2),
      ])),
      equals(
        '''
{
  "gitHash": "ca799fa8b2254d09664b78ee80c43b434788d112",
  "results": {
    "BM_PaintRecordInit": {
      "default": {
        "cpu_time": 101.0,
        "options": {
          "cpu_scaling_enabled": "true",
          "library_build_type": "release",
          "mhz_per_cpu": "2594",
          "num_cpus": "56",
          "unit": "ns",
          "originId": "flutter-center"
        },
        "real_time": 102.0
      }
    }
  }
}''',
      ),
    );
  });

  test('Throw if points have the same name but different options', () {
    final enginePoint1 = FlutterEngineMetricPoint(
      'BM_PaintRecordInit',
      101,
      'ca799fa8b2254d09664b78ee80c43b434788d112',
      moreTags: {
        kSubResultKey: 'cpu_time',
        kUnitKey: 'ns',
        'cpu_scaling_enabled': 'true',
      },
    );
    final enginePoint2 = FlutterEngineMetricPoint(
      'BM_PaintRecordInit',
      102,
      'ca799fa8b2254d09664b78ee80c43b434788d112',
      moreTags: {
        kSubResultKey: 'real_time',
        kUnitKey: 'ns',
        'cpu_scaling_enabled': 'false',
      },
    );

    final JsonEncoder encoder = JsonEncoder.withIndent('  ');
    expect(
      () => encoder.convert(SkiaPerfPoint.toSkiaPerfJson(<SkiaPerfPoint>[
        SkiaPerfPoint.fromPoint(enginePoint1),
        SkiaPerfPoint.fromPoint(enginePoint2),
      ])),
      throwsA(anything),
    );
  });

  test('SkiaPerfDestination correctly updates points', () async {
    final mockGcs = MockSkiaPerfGcsAdaptor();
    final dst = SkiaPerfDestination(mockGcs);
    await dst.update(<MetricPoint>[cocoonPointRev1Metric1]);
    await dst.update(<MetricPoint>[cocoonPointRev1Metric2]);
    List<SkiaPerfPoint> points = await mockGcs.readPoints(
        await SkiaPerfGcsAdaptor.comptueObjectName(
            kFlutterFrameworkRepo, frameworkRevision1));
    expect(points.length, equals(2));
    expectSetMatch<String>(
        points.map((SkiaPerfPoint p) => p.originId), [kCocoonId, kCocoonId]);
    expectSetMatch(points.map((SkiaPerfPoint p) => p.name), [taskName]);
    expectSetMatch(points.map((SkiaPerfPoint p) => p.subResult), [metric1, metric2]);
    expectSetMatch(points.map((SkiaPerfPoint p) => p.value), [value1, value2]);

    await dst.update(<MetricPoint>[cocoonPointRev1Metric1, cocoonPointRev2Metric1]);
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
      equals('flutter-flutter/2019/12/04/23/$frameworkRevision1/values.json'),
    );
    expect(
      await SkiaPerfGcsAdaptor.comptueObjectName(
          kFlutterEngineRepo, engineRevision1),
      equals('flutter-engine/2019/12/03/20/$engineRevision1/values.json'),
    );
    expect(
      await SkiaPerfGcsAdaptor.comptueObjectName(
          kFlutterEngineRepo, engineRevision2),
      equals('flutter-engine/2020/01/03/15/$engineRevision2/values.json'),
    );
  });

  test('SkiaPerfGcsAdaptor passes end-to-end test with Google Cloud Storage',
      () async {
    final Map<String, dynamic> credentialsJson = getGcpCredentialsJson();
    final credentials = ServiceAccountCredentials.fromJson(credentialsJson);

    final client = await clientViaServiceAccount(credentials, Storage.SCOPES);
    final storage = Storage(client, credentialsJson['project_id']);

    expect(await storage.bucketExists(SkiaPerfDestination.kTestBucketName),
        isTrue);
    final Bucket testBucket =
        storage.bucket(SkiaPerfDestination.kTestBucketName);
    final skiaPerfGcs = SkiaPerfGcsAdaptor(testBucket);

    final String testObjectName = await SkiaPerfGcsAdaptor.comptueObjectName(
        kFlutterFrameworkRepo, frameworkRevision1);

    await skiaPerfGcs.writePoints(testObjectName, <SkiaPerfPoint>[
      SkiaPerfPoint.fromPoint(cocoonPointRev1Metric1),
      SkiaPerfPoint.fromPoint(cocoonPointRev1Metric2),
    ]);

    final List<SkiaPerfPoint> points =
        await skiaPerfGcs.readPoints(testObjectName);
    expect(points.length, equals(2));
    expectSetMatch<String>(
        points.map((SkiaPerfPoint p) => p.originId), [kCocoonId, kCocoonId]);
    expectSetMatch(points.map((SkiaPerfPoint p) => p.name), [taskName]);
    expectSetMatch(points.map((SkiaPerfPoint p) => p.subResult), [metric1, metric2]);
    expectSetMatch(points.map((SkiaPerfPoint p) => p.value), [value1, value2]);
    expectSetMatch(
        points.map((SkiaPerfPoint p) => p.githubRepo), [kFlutterFrameworkRepo]);
    expectSetMatch(
        points.map((SkiaPerfPoint p) => p.gitHash), [frameworkRevision1]);
    for (int i = 0; i < 2; i += 1) {
      expect(points[0].jsonUrl, startsWith('https://'));
      expect(points[0].sourceTime, isNotNull);
    }
  });

  test('SkiaPerfGcsAdaptor end-to-end test with engine points', () async {
    final Map<String, dynamic> credentialsJson = getGcpCredentialsJson();
    final credentials = ServiceAccountCredentials.fromJson(credentialsJson);

    final client = await clientViaServiceAccount(credentials, Storage.SCOPES);
    final storage = Storage(client, credentialsJson['project_id']);

    expect(await storage.bucketExists(SkiaPerfDestination.kTestBucketName),
        isTrue);

    final Bucket testBucket =
        storage.bucket(SkiaPerfDestination.kTestBucketName);
    final skiaPerfGcs = SkiaPerfGcsAdaptor(testBucket);

    final String testObjectName = await SkiaPerfGcsAdaptor.comptueObjectName(
        kFlutterEngineRepo, engineRevision);

    await skiaPerfGcs.writePoints(testObjectName, <SkiaPerfPoint>[
      SkiaPerfPoint.fromPoint(enginePoint1),
      SkiaPerfPoint.fromPoint(enginePoint2),
    ]);

    final List<SkiaPerfPoint> points =
        await skiaPerfGcs.readPoints(testObjectName);
    expect(points.length, equals(2));
    expectSetMatch<String>(
      points.map((SkiaPerfPoint p) => p.originId),
      [kFlutterCenterId, kFlutterCenterId],
    );
    expectSetMatch(
      points.map((SkiaPerfPoint p) => p.name),
      [engineMetricName, engineMetricName],
    );
    expectSetMatch(
      points.map((SkiaPerfPoint p) => p.value),
      [engineValue1, engineValue2],
    );
    expectSetMatch(
      points.map((SkiaPerfPoint p) => p.githubRepo),
      [kFlutterEngineRepo],
    );
    expectSetMatch(
        points.map((SkiaPerfPoint p) => p.gitHash), [engineRevision]);
    for (int i = 0; i < 2; i += 1) {
      expect(points[0].jsonUrl, startsWith('https://'));
      expect(points[0].sourceTime, isNotNull);
    }
  });

  test('SkiaPerfDestination can write new points of a commit revision.',
      () async {
    final Map<String, dynamic> credentialsJson = getGcpCredentialsJson();
    final credentials = ServiceAccountCredentials.fromJson(credentialsJson);

    // First, delete the existing GCS object of that commit revision
    final client = await clientViaServiceAccount(credentials, Storage.SCOPES);
    final storage = Storage(client, credentialsJson['project_id']);
    final Bucket testBucket =
        storage.bucket(SkiaPerfDestination.kTestBucketName);
    final String testObjectName = await SkiaPerfGcsAdaptor.comptueObjectName(
        kFlutterFrameworkRepo, frameworkRevision1);
    try {
      await testBucket.delete(testObjectName);
    } catch (e) {
      if (!e.toString().contains('No such object')) {
        rethrow;
      }
    }

    // Second, update the points
    final destination = await SkiaPerfDestination.makeFromGcpCredentials(
        credentialsJson,
        isTesting: true);
    await destination.update([cocoonPointRev1Metric1]);
  });
}
