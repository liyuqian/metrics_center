import 'package:test/test.dart';

import 'package:metrics_center/src/common.dart';
import 'package:metrics_center/src/flutter/destination.dart';
import 'package:metrics_center/src/flutter/center.dart';

import 'utility.dart';

const String kTestSourceId = 'test';

@Timeout(Duration(seconds: 3600))
void main() {
  test('FlutterDestination update does not crash.', () async {
    FlutterDestination dst = await FlutterDestination.makeFromCredentialsJson(
        getGcpCredentialsJson());
    await dst.update(<MetricPoint>[MetricPoint(1.0, {}, kTestSourceId, null)]);
  });

  // The following test exercises both FlutterSource and FlutterDestination
  test('FlutterCenter writes successfully and reads sorted data.', () async {
    final center =
        await FlutterCenter.makeFromCredentialsJson(getGcpCredentialsJson());

    // Set sourceTimeMicros for existing points so they won't affect this test.
    await center.synchronize();

    final points = <MetricPoint>[
      MetricPoint(1.0, {'t': '0', 'y': 'b'}, kTestSourceId, null),
      MetricPoint(2.0, {'t': '1'}, kTestSourceId, null),
      MetricPoint(3.0, {'t': '2'}, kTestSourceId, null),
      MetricPoint(4.0, {'t': '3'}, kTestSourceId, null),
      MetricPoint(5.0, {'t': '4'}, kTestSourceId, null),
    ];

    final timeBeforeInsert = <DateTime>[];

    for (int i = 0; i < 5; i += 1) {
      timeBeforeInsert.add(DateTime.now());
      await Future.delayed(Duration(milliseconds: 1));
      await center.update(<MetricPoint>[points[i]]);
      final List<MetricPoint> readBeforeSync =
          await center.getUpdatesAfter(timeBeforeInsert[i]);
      expect(readBeforeSync.length, equals(0));
      await center.synchronize();
      final List<MetricPoint> readAfterSync =
          await center.getUpdatesAfter(timeBeforeInsert[i]);
      expect(readAfterSync.length, equals(1));
    }

    List<MetricPoint> readAll =
        await center.getUpdatesAfter(timeBeforeInsert[0]);

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

  // TODO test other functions
}
