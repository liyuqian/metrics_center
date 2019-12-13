import 'dart:collection';

/// Common format of a metric data point
class Point {
  Point(
    this.value,
    Map<String, dynamic> tags,
    this.originId,
    this.sourceTime,
  )   : assert(value != null),
        assert(tags != null),
        assert(originId != null),
        this._tags = SplayTreeMap.from(tags);

  /// Can store integer values
  final double value;

  /// Test name, unit, timestamp, configs, git revision, ..., in sorted order
  UnmodifiableMapView<String, String> get tags =>
      UnmodifiableMapView<String, String>(_tags);

  /// Unique identifier for updating existing data point.
  ///
  /// This id should stay constant even if the [tags.keys] are reordered.
  /// (Because we are using an ordered SplayTreeMap to generate the id.)
  String get id => '$originId: $_tags';

  /// Where this point originally comes from. Used for dedup.
  ///
  /// This should stay constant as the point is transferred among multiple
  /// sources and destinations.
  final String originId;

  /// The last modified time of this point in a [MetricsSource]. Can be null if
  /// this point isn't loaded from a source (e.g., it's constructed in memory).
  final DateTime sourceTime;

  final SplayTreeMap<String, String> _tags;
}

/// Source must support efficient index on [Point.sourceTime]
/// so we can query with a time range.
abstract class MetricsSource<SourcePoint extends Point> {
  /// Return points updated since timestamp [timestamp] exclusively. (i.e., data
  /// with sourceTime = [timestamp] won't be returned.)
  ///
  /// The returned points should be sorted by their srcTimeNanos ascendingly.
  Future<List<SourcePoint>> getUpdatesAfter(DateTime timestamp);

  /// Unique id of the source. If this source is also a destination, then its
  /// corresponding destination (often the same object, e.g., [MetricsCenter])
  /// should have the same id.
  String get id;
}

abstract class MetricsDestination {
  /// Insert new data points or modify old ones with matching id.
  ///
  /// Deletion is done by setting [Point.value] to [double.nan].
  ///
  /// The destination may not actually delete or update the point with the
  /// matching id. It can simply append a new point to the database (e.g.,
  /// [FlutterMetricsCenter] does that with Google BigQuery). Because the
  /// timestamp of the new point will be set to the latest,
  /// [FlutterMetricsCenter] will correctly synchronize that new point with all
  /// destinations.
  ///
  /// The destination could also ignore some points and not store them. For the
  /// non-ignored points, it should faithfully store the value, tags, raw, and
  /// originId fields. Thus, if this destination is also a source (e.g., a
  /// [MetricsCenter]), then when [getUpdatesAfter] is called on the source, we
  /// should get the points with exactly the same fields that we just updated.
  /// This is especially important for the originId field which is used for
  /// dedup. Otherwise, there might be an update loop to generate an infinite
  /// amount of duplicate points.
  Future<void> update(List<Point> points);

  /// Unique id of the destination. If this destination is also a source, then
  /// its corresponding destination (often the same object, e.g.,
  /// [MetricsCenter]) should have the same id.
  String get id;
}

/// A central data warehouse to pull metrics from multiple sources, and send
/// them to multiple destinations for consumption.
abstract class MetricsCenter
    implements MetricsSource<Point>, MetricsDestination {
  List<MetricsSource> otherSources = [];
  List<MetricsDestination> otherDestinations = [];

  Future<void> periodicallySync() async {
    await Future.wait(otherSources.map(pullFromSource));
    await Future.wait(otherDestinations.map(pushToDestination));
  }

  Future<void> pushToDestination(MetricsDestination destination) async {
    // To dedup, do not send data from that destination. This is important as
    // some destinations are also sources (e.g., a [MetricsCenter]).
    List<Point> points =
        (await getUpdatesAfter(dstUpdateTime[destination.id])).where(
      (p) => p.originId != destination.id,
    ).toList();
    await destination.update(points);
    assert(points.last.sourceTime != null);
    dstUpdateTime[destination.id] = points.last.sourceTime;
  }

  Future<void> pullFromSource(MetricsSource source) async {
    // To dedup, don't pull any data from other sources. This is important as
    // some sources are also destinations (e.g., [MetricsCenter]), and data from
    // other sources could be pushed there.
    List<Point> points =
        (await source.getUpdatesAfter(srcUpdateTime[source.id]))
            .where((p) => p.originId == source.id);
    await update(points);
    assert(points.last.sourceTime != null);
    srcUpdateTime[source.id] = points.last.sourceTime;
  }

  /// Map from a source id to the largest sourceTime timestamp of any data that
  /// this center has pulled from it.
  ///
  /// The timestamp is generated in the source, and it may have a clock that's
  /// not in sync with the [MetricsCenter]'s clock.
  ///
  /// We only require that the source's clock is strictly increasing between
  /// batches: if [getUpdateAfter] already returned a list of data points with
  /// the largest [sourceTime] = x, then the later updates must have strictly
  /// greater [sourceTime] > x.
  Map<String, DateTime> srcUpdateTime;

  /// Map from a destination id to the largest sourceTime of any data that this
  /// center has pushed to it.
  ///
  /// This timestamp is generated by [MetricsCenter] (a [MetricsSource]) so its
  /// [sourceTime] is strictly increasing between batches.
  Map<String, DateTime> dstUpdateTime;
}

/// Some common tag keys
const String kGithubRepoKey = 'gitRepo';
const String kGitRevisionKey = 'gitRevision';
const String kOriginIdKey = 'originId';
const String kTaskNameKey = 'taskName';
const String kUnitKey = 'unit';
const String kNameKey = 'name';

/// Known source/destination ids
const String kCocoonId = 'cocoon';
const String kSkiaPerfId = 'skiaperf';
const String kFlutterCenterId = 'flutter-center';

/// Known github repo
const String kFlutterFrameworkRepo = 'flutter/flutter';
const String kFlutterEngineRepo = 'flutter/engine';
