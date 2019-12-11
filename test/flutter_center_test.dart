import 'package:test/test.dart';

import 'package:metrics_center/base.dart';
import 'package:metrics_center/flutter.dart';

import 'utility.dart';

void main() {
  test('FlutterDestination updates with makeFromCredentialsJson does not crash.', () async {
    FlutterDestination dst = await FlutterDestination.makeFromCredentialsJson(
        getGcpCredentialsJson());
    final BasePoint cocoonPointRev1Name1 = BasePoint(1.0, {}, kFlutterCenterId, null);
    final Iterable<Point> iterable = <BasePoint>[cocoonPointRev1Name1];
    await dst.update(
      iterable,
    );
  });
}
