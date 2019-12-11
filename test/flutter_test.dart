import 'package:test/test.dart';

import 'package:metrics_center/base.dart';
import 'package:metrics_center/flutter.dart';

import 'utility.dart';

Future<void> _ensureTableExists() async {
  final center =
      await FlutterCenter.makeFromCredentialsJson(getGcpCredentialsJson());
  await center.createTableIfNeeded();
}

void main() {
  test('FlutterDestination update does not crash.', () async {
    await _ensureTableExists();
    FlutterDestination dst = await FlutterDestination.makeFromCredentialsJson(
        getGcpCredentialsJson());
    await dst.update(<BasePoint>[BasePoint(1.0, {}, kFlutterCenterId, 0)]);
  });

  // TODO test getUpdates and other functions
}
