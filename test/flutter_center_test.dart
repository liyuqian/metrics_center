@Timeout(Duration(seconds: 3600))

import 'dart:math';

import 'package:gcloud/db.dart';
import 'package:test/test.dart';

import 'package:metrics_center/src/common.dart';
import 'package:metrics_center/src/flutter/center.dart';
import 'package:metrics_center/src/flutter/common.dart';
import 'package:metrics_center/src/flutter/destination.dart';
import 'package:metrics_center/src/flutter/source.dart';

import 'utility.dart';

const String kTestSourceId = 'test';

// This test may be affected by flutter_destination_test.dart if they're
// running concurrently. Therefore `pub run test test -j1` is recommended
void main() {
  test('Exercise both FlutterSource and FlutterDestination.', () async {
    final db = await datastoreFromCredentialsJson(getGcpCredentialsJson());
    final flutterSrc = FlutterSource(db);
    final flutterDst = FlutterDestination(db);

    // Set sourceTime for existing points so they won't affect this test. The
    // test should use a test specific GCP project or a mock datastore to ensure
    // that during the test, no one except this test is writing into this
    // FlutterDestination. Otherwise the test will be flaky.
    await flutterSrc.updateSourceTime();

    final points = <MetricPoint>[
      MetricPoint(1.0, {'t': '0', 'y': 'b'}, kTestSourceId),
      MetricPoint(2.0, {'t': '1'}, kTestSourceId),
      MetricPoint(3.0, {'t': '2'}, kTestSourceId),
      MetricPoint(4.0, {'t': '3'}, kTestSourceId),
      MetricPoint(5.0, {'t': '4'}, kTestSourceId),
    ];

    final timeBeforeInsert = <DateTime>[];

    for (int i = 0; i < 5; i += 1) {
      timeBeforeInsert.add(DateTime.now());
      await Future.delayed(Duration(milliseconds: 1));
      await flutterDst.update(<MetricPoint>[points[i]]);
      final List<MetricPoint> readBeforeSync =
          await flutterSrc.getUpdatesAfter(timeBeforeInsert[i]);
      expect(readBeforeSync.length, equals(0));
      await flutterSrc.updateSourceTime();
      final List<MetricPoint> readAfterSync =
          await flutterSrc.getUpdatesAfter(timeBeforeInsert[i]);
      expect(readAfterSync.length, equals(1));
    }

    List<MetricPoint> readAll =
        await flutterSrc.getUpdatesAfter(timeBeforeInsert[0]);

    expect(readAll.length, equals(5));
    for (int i = 0; i < 5; i += 1) {
      expect(readAll.elementAt(i).id, equals(points[i].id));
      expect(readAll.elementAt(i).value, equals(points[i].value));
      expect(
        readAll.elementAt(i).sourceTime.microsecondsSinceEpoch,
        greaterThan(timeBeforeInsert[i].microsecondsSinceEpoch),
      );
      if (i < 4) {
        expect(
          readAll.elementAt(i).sourceTime.microsecondsSinceEpoch,
          lessThan(timeBeforeInsert[i + 1].microsecondsSinceEpoch),
        );
      }
    }
  });

  test('FlutterCenter synchronize works.', () async {
    final db = await datastoreFromCredentialsJson(getGcpCredentialsJson());

    final twoPointSource = TwoPointSource();
    final countDestination = CountDestination();
    final countDestination2 = CountDestination2();

    final DateTime t0 = DateTime.now();

    final center = FlutterCenter(
      db,
      otherSources: [twoPointSource],
      otherDestinations: [countDestination, countDestination2],
      srcUpdateTime: {twoPointSource.id: t0},
      dstUpdateTime: {countDestination.id: t0, countDestination2.id: t0},
    );
    final flutterSrc = FlutterSource(db);

    // Set sourceTime for existing points so they won't affect this test. The
    // test should use a test specific GCP project or a mock datastore to ensure
    // that during the test, no one except this test is writing into this
    // FlutterDestination. Otherwise the test will be flaky.
    await flutterSrc.updateSourceTime();

    // The MockSource always returns 2 points, one with originId = kMockId, and
    // one with a different id.
    expect(
      (await twoPointSource.getUpdatesAfter(DateTime.now())).length,
      equals(2),
    );

    // Initial check of 0
    expect(countDestination.updateCount, equals(0));
    expect(countDestination2.updateCount, equals(0));

    await center.synchronize();
    final List<MetricPoint> pointsAfterT0 =
        await flutterSrc.getUpdatesAfter(t0);

    // We should only take one point with originId = kMockId, and discard the
    // other one with originId != kMockId.
    expect(pointsAfterT0.length, equals(1));

    // mockDestination receives no update due to dedup, but mockDestination2
    // receives one because its id is different from mockDestination's.
    expect(countDestination.updateCount, equals(0));
    expect(countDestination2.updateCount, equals(1));

    final flutterDst = FlutterDestination(db);
    await flutterDst.update([MetricPoint(1.0, {}, kTestSourceId)]);
    await center.synchronize();

    // mockDestination should receive one update from the FlutterDestination
    // update above.
    expect(countDestination.updateCount, equals(1));

    // mockDestination2 should receive two more updates: 1 from
    // FlutterDestination, 1 from mockSource
    expect(countDestination2.updateCount, equals(3));
  });

  test('FlutterCenter loads and writes src/dstUpdateTime.', () async {
    final db = await datastoreFromCredentialsJson(getGcpCredentialsJson());

    final timedSource = TimedSource();
    final timedDestination = TimedDestination();
    final flutterSource = TimedFlutterSource(db);

    final t0 = DateTime.now();

    {
      final center = FlutterCenter(
        db,
        flutterSource: flutterSource,
        otherSources: [timedSource],
        otherDestinations: [timedDestination],
      );
      await Future.delayed(Duration(milliseconds: 1));
      timedSource.sourceTime = DateTime.now();
      await center.synchronize();

      // In these first tests, (1) timedSource.queryTime should be equal to
      // _srcUpdateTime[kMockId] and it should be less than t0; (2)
      // flutterSource.queryTime should be equal to _dstUpdateTime[kMockId] and
      // it should be less than t0.
      expect(
        timedSource.queryTime.microsecondsSinceEpoch,
        lessThan(t0.microsecondsSinceEpoch),
      );
      expect(
        flutterSource.queryTime.microsecondsSinceEpoch,
        lessThan(t0.microsecondsSinceEpoch),
      );
    }

    {
      final center = FlutterCenter(
        db,
        flutterSource: flutterSource,
        otherSources: [timedSource],
        otherDestinations: [timedDestination],
      );
      await Future.delayed(Duration(milliseconds: 1));
      timedSource.sourceTime = DateTime.now();
      await center.synchronize();

      // In these first tests, (1) timedSource.queryTime should be equal to
      // _srcUpdateTime[kMockId] and it should be greater than t0; (2)
      // flutterSource.queryTime should be equal to _dstUpdateTime[kMockId] and
      // it should be greater than t0.
      expect(
        timedSource.queryTime.microsecondsSinceEpoch,
        lessThan(t0.microsecondsSinceEpoch),
      );
      expect(
        flutterSource.queryTime.microsecondsSinceEpoch,
        lessThan(t0.microsecondsSinceEpoch),
      );
     }
  });
}

const String kMockId = 'mock';

class TwoPointSource extends MetricSource {
  @override
  Future<List<MetricPoint>> getUpdatesAfter(DateTime timestamp) async {
    return <MetricPoint>[
      MetricPoint(1.0, {}, kMockId, timestamp.add(_kTiny)),
      MetricPoint(2.0, {}, kFlutterCenterId, timestamp.add(_kTiny)),
    ];
  }

  @override
  String get id => kMockId;

  static final _kTiny = Duration(microseconds: 1);
}

// Count how many points have been updated.
class CountDestination extends MetricDestination {
  @override
  String get id => kMockId;

  @override
  Future<void> update(List<MetricPoint> points) async {
    updateCount += points.length;
  }

  int updateCount = 0;
}

// Have a different id so this can receive updates from MockSrouce.
class CountDestination2 extends CountDestination {
  @override
  String get id => '$kMockId 2';

  @override
  Future<void> update(List<MetricPoint> points) async {
    updateCount += points.length;
  }
}

class TimedSource extends MetricSource {
  @override
  String get id => kMockId;

  @override
  Future<List<MetricPoint>> getUpdatesAfter(DateTime timestamp) async {
    queryTime = timestamp;
    return [MetricPoint(0, {}, kMockId, sourceTime)];
  }

  DateTime sourceTime;
  DateTime queryTime;
}

class TimedDestination extends MetricDestination {
  @override
  String get id => kMockId;

  @override
  Future<void> update(List<MetricPoint> points) async {
    queryTime = DateTime.fromMicrosecondsSinceEpoch(
        points.map((x) => x.sourceTime.microsecondsSinceEpoch).reduce(max));
  }

  DateTime queryTime;
}

class TimedFlutterSource extends FlutterSource {
  TimedFlutterSource(DatastoreDB db) : super(db);

  @override
  Future<List<MetricPoint>> getUpdatesAfter(DateTime timestamp) {
    queryTime = timestamp;
    return super.getUpdatesAfter(timestamp);
  }

  DateTime queryTime;
}
