import 'package:test/test.dart';

import 'package:metrics_center/base.dart';
import 'package:metrics_center/flutter.dart';

import 'utility.dart';

@Timeout(const Duration(seconds: 3600))

void main() {
  test('FlutterDestination update does not crash.', () async {
    await _ensureTableExists();
    FlutterDestination dst = await FlutterDestination.makeFromCredentialsJson(
        getGcpCredentialsJson());
    await dst.update(<BasePoint>[BasePoint(1.0, {}, kFlutterCenterId, 0)]);
  });

  // TODO(liyuqian): figure out why the first write after creating the table
  // seems to fail without any error from BigqueryApi.
  test('FlutterCenter writes successfully and reads sorted data.', () async {
    final center =
        await FlutterCenter.makeFromCredentialsJson(getGcpCredentialsJson());
    await center.createTableIfNeeded();
    int nowNanos = DateTime.now().microsecondsSinceEpoch * 1000;
    final points = <BasePoint>[
      BasePoint(1.0, {'t': '0', 'y': 'b'}, kFlutterCenterId, nowNanos),
      BasePoint(2.0, {'t': '1'}, kFlutterCenterId, nowNanos + 1),
      BasePoint(5.0, {'t': '4'}, kFlutterCenterId, nowNanos + 4),
      BasePoint(4.0, {'t': '3'}, kFlutterCenterId, nowNanos + 3),
      BasePoint(3.0, {'t': '2'}, kFlutterCenterId, nowNanos + 2),
    ];
    await center.update(points);

    // Sorted points in srcTimeNanos. Method getUpdatesAfter should return
    // points in this order.
    final sortedPoints = <BasePoint>[
      points[0],
      points[1],
      points[4],
      points[3],
      points[2],
    ];

    Iterable<BasePoint> readAll = await center.getUpdatesAfter(nowNanos - 1);
    Iterable<BasePoint> readOne = await center.getUpdatesAfter(nowNanos + 3);

    expect(readAll.length, equals(5));
    expect(readOne.length, equals(1));

    for (int i = 0; i < 5; i += 1) {
      expect(readAll.elementAt(i).id, equals(sortedPoints[i].id));
      expect(readAll.elementAt(i).value, equals(sortedPoints[i].value));
    }

    expect(readOne.elementAt(0).id, equals(sortedPoints[4].id));
    expect(readOne.elementAt(0).value, equals(sortedPoints[4].value));
  });

  // TODO test getUpdates and other functions
}

Future<void> _ensureTableExists() async {
  final center =
      await FlutterCenter.makeFromCredentialsJson(getGcpCredentialsJson());
  await center.createTableIfNeeded();
}
