import 'package:test/test.dart';

import 'package:metrics_center/base.dart';
import 'package:metrics_center/flutter/center.dart';

import 'utility.dart';

@Timeout(const Duration(seconds: 3600))
void main() {
  test('FlutterDestination update does not crash.', () async {
    await _ensureTableExists();
    FlutterDestination dst = await FlutterDestination.makeFromCredentialsJson(
        getGcpCredentialsJson());
    await dst.update(<BasePoint>[BasePoint(1.0, {}, kFlutterCenterId, null)]);
  });

  // // TODO(liyuqian): figure out why the first write after creating the table
  // // seems to fail without any error from BigqueryApi.
  // test('FlutterCenter writes successfully and reads sorted data.', () async {
  //   final center =
  //       await FlutterCenter.makeFromCredentialsJson(getGcpCredentialsJson());
  //   await center.createTableIfNeeded();
  //   final points = <BasePoint>[
  //     BasePoint(1.0, {'t': '0', 'y': 'b'}, kFlutterCenterId, null),
  //     BasePoint(2.0, {'t': '1'}, kFlutterCenterId, null),
  //     BasePoint(3.0, {'t': '2'}, kFlutterCenterId, null),
  //     BasePoint(4.0, {'t': '3'}, kFlutterCenterId, null),
  //     BasePoint(5.0, {'t': '4'}, kFlutterCenterId, null),
  //   ];

  //   final timeBeforeInsert = <DateTime>[];

  //   const Duration ms1 = Duration(milliseconds: 1);
  //   for (int i = 0; i < 5; i += 1) {
  //     timeBeforeInsert.add(DateTime.now());
  //     await Future.delayed(ms1);
  //     center.update(<BasePoint>[points[i]]);
  //     final List<BasePoint> readBeforeSync =
  //         await center.getUpdatesAfter(timeBeforeInsert[i]);
  //     expect(readBeforeSync.length, equals(0));
  //     center.synchronize();
  //     await Future.delayed(ms1);
  //     final List<BasePoint> readAfterSync =
  //         await center.getUpdatesAfter(timeBeforeInsert[i]);
  //     expect(readAfterSync.length, equals(1));
  //   }

  //   List<BasePoint> readAll = await center.getUpdatesAfter(timeBeforeInsert[0]);

  //   expect(readAll.length, equals(5));
  //   for (int i = 0; i < 5; i += 1) {
  //     expect(readAll.elementAt(i).id, equals(points[i].id));
  //     expect(readAll.elementAt(i).value, equals(points[i].value));
  //     final DateTime sourceTime = readAll.elementAt(i).sourceTime;
  //     expect(sourceTime, greaterThan(timeBeforeInsert[i]));
  //     if (i < 4) {
  //       expect(sourceTime, lessThan(timeBeforeInsert[i + 1]));
  //     }
  //   }
  // });

  // TODO test getUpdates and other functions
}

Future<void> _ensureTableExists() async {
  final center =
      await FlutterCenter.makeFromCredentialsJson(getGcpCredentialsJson());
  await center.createTableIfNeeded();
}
