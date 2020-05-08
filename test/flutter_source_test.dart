import 'package:metrics_center/src/common.dart';
import 'package:metrics_center/src/flutter/common.dart';
import 'package:metrics_center/src/flutter/source.dart';
import 'package:test/test.dart';
import 'src/fake_datastore.dart';

void main() {
  group('getUpdatesAfter', () {
    FakeDatastoreDB fakeDB;
    FlutterSource source;

    setUp(() async {
      fakeDB = FakeDatastoreDB();
      source = FlutterSource(fakeDB);
    });

    test('gets empty updates', () async {
      List<MetricPoint> points =
          await source.getUpdatesAfter(DateTime.fromMicrosecondsSinceEpoch(10));
      expect(points, isEmpty);
    });

    test('gets 2 updates', () async {
      MetricPoint point1 = MetricPoint(
        0.0,
        <String, dynamic>{'gitRevision': 'sha1'},
        'flutter-center',
        DateTime.fromMicrosecondsSinceEpoch(20),
      );
      MetricPointModel model1 = MetricPointModel(from: point1)
        ..parentKey = fakeDB.emptyKey
        ..sourceTimeMicros = 20;
      MetricPoint point2 = MetricPoint(
        0.0,
        <String, dynamic>{'gitRevision': 'sha2'},
        'flutter-center',
        DateTime.fromMicrosecondsSinceEpoch(30),
      );
      MetricPointModel model2 = MetricPointModel(from: point2)
        ..parentKey = fakeDB.emptyKey
        ..sourceTimeMicros = 30;

      fakeDB.values[model1.key] = model1;
      fakeDB.values[model2.key] = model2;

      List<MetricPoint> points =
          await source.getUpdatesAfter(DateTime.fromMicrosecondsSinceEpoch(10));
      expect(points, <MetricPoint>[point1, point2]);
    });
  });

  group('updateSourceTime', () {
    FakeDatastoreDB fakeDB;
    FlutterSource source;

    setUp(() async {
      fakeDB = FakeDatastoreDB();
      source = FlutterSource(fakeDB);
    });

    test('sets source time', () async {
      MetricPoint point1 = MetricPoint(
        0.0,
        <String, dynamic>{'gitRevision': 'sha1'},
        'flutter-center',
        null,
      );
      MetricPointModel model1 = MetricPointModel(from: point1)
        ..parentKey = fakeDB.emptyKey
        ..sourceTimeMicros = null;
      MetricPoint point2 = MetricPoint(
        0.0,
        <String, dynamic>{'gitRevision': 'sha2'},
        'flutter-center',
        null,
      );
      MetricPointModel model2 = MetricPointModel(from: point2)
        ..parentKey = fakeDB.emptyKey
        ..sourceTimeMicros = null;

      fakeDB.values[model1.key] = model1;
      fakeDB.values[model2.key] = model2;

      await source.updateSourceTime();

      expect(model1.sourceTimeMicros, isNotNull);
      expect(model2.sourceTimeMicros, isNotNull);
    });
  });
}
