import 'package:metrics_center/base.dart';

class FlutterMetricsCenter extends MetricsCenter {
  @override
  Future<Iterable<BasePoint>> getUpdatesAfter(int timeNanos) {
    // TODO: implement getUpdatesAfter
    return null;
  }

  @override
  String get id => 'flutter-center';

  @override
  Future<void> update(Iterable<Point> points) {
    // TODO: implement update
    return null;
  }

}