import 'dart:collection';

/// Common format of a metric data point
abstract class Point {
  /// Can store integer values
  double get value;

  /// Test name, unit, timestamp, configs, git revision, ..., in sorted order
  UnmodifiableMapView<String, String> get tags;

  /// Unique identifier for updating existing data point.
  ///
  /// This id should stay constant even if the [tags.keys] are reordered.
  String get id;

  /// Where this comes from. Used for dedup.
  String get sourceId;

  /// The last modified time of this point in a [MetricsSource]. Can be null if
  /// this point isn't loaded from a source (e.g., it's constructed in memory).
  int get srcTimeNanos;
}

/// Base implementation of [Point] used by the [MetricsCenter].
class BasePoint extends Point {
  BasePoint(
    this.value,
    Map<String, dynamic> tags,
    this.sourceId,
    this.srcTimeNanos,
  ) : this._tags = SplayTreeMap.from(tags) {}

  @override
  final double value;

  @override
  UnmodifiableMapView<String, String> get tags =>
      UnmodifiableMapView<String, String>(_tags);

  @override
  String get id => '$sourceId: $_tags';

  @override
  final String sourceId;

  @override
  final int srcTimeNanos; // the last modified time

  final SplayTreeMap<String, String> _tags;
}

/// Source must support efficient index on [Point.srcTimeNanos]
/// so we can query with a time range.
abstract class MetricsSource<SourcePoint extends Point> {
  /// Return points updated since timestamp [timeNanos] exclusively. (i.e., data
  /// with srcTimeNanos = [timeNanos] won't be returned.)
  ///
  /// The returned points should be sorted by their srcTimeNanos ascendingly.
  Future<Iterable<SourcePoint>> getUpdatesAfter(int timeNanos);

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
  /// sourceId fields. Thus, if this destination is also a source (e.g., a
  /// [MetricsCenter]), then when [getUpdatesAfter] is called on the source, we
  /// should get the points with exactly the same fields that we just updated.
  /// This is especially important for the sourceId field which is used for
  /// dedup. Otherwise, there might be an update loop to generate an infinite
  /// amount of duplicate points.
  Future<void> update(Iterable<Point> points);

  /// Unique id of the destination. If this destination is also a source, then
  /// its corresponding destination (often the same object, e.g.,
  /// [MetricsCenter]) should have the same id.
  String get id;
}

/// A central data warehouse to pull metrics from multiple sources, and send
/// them to multiple destinations for consumption.
abstract class MetricsCenter
    implements MetricsSource<BasePoint>, MetricsDestination {
  List<MetricsSource> otherSources;
  List<MetricsDestination> otherDestinations;

  Future<void> periodicallySync() async {
    await Future.wait(otherSources.map(pullFromSource));
    await Future.wait(otherDestinations.map(pushToDestination));
  }

  Future<void> pushToDestination(MetricsDestination destination) async {
    // To dedup, do not send data from that destination. This is important as
    // some destinations are also sources (e.g., a [MetricsCenter]).
    Iterable<Point> points =
        (await getUpdatesAfter(dstUpdateNanos[destination.id])).where(
      (p) => p.sourceId != destination.id,
    );
    await destination.update(points);
    assert(points.last.srcTimeNanos != null);
    dstUpdateNanos[destination.id] = points.last.srcTimeNanos;
  }

  Future<void> pullFromSource(MetricsSource source) async {
    // To dedup, don't pull any data from other sources. This is important as
    // some sources are also destinations (e.g., [MetricsCenter]), and data from
    // other sources could be pushed there.
    Iterable<Point> points =
        (await source.getUpdatesAfter(srcUpdateNanos[source.id]))
            .where((p) => p.sourceId == source.id);
    await update(points);
    assert(points.last.srcTimeNanos != null);
    srcUpdateNanos[source.id] = points.last.srcTimeNanos;
  }

  /// Map from a source id to the largest srcTimeNanos timestamp of any data
  /// that this center has pulled from it.
  ///
  /// The timestamp is generated in the source, and it may have a clock that's
  /// not in sync with the [MetricsCenter]'s clock.
  ///
  /// We only require that the source's clock is strictly increasing between
  /// batches: if [getUpdateAfter] already returned a list of data points with
  /// the largest [srcTimeNanos] = x, then the later updates must have strictly
  /// greater [srcTimeNanos] > x.
  Map<String, int> srcUpdateNanos;

  /// Map from a destination id to the largest srcTimeNanos timestamp of any
  /// data that this center has pushed to it.
  ///
  /// This timestamp is generated by [MetricsCenter] (a [MetricsSource]) so its
  /// [srcTimeNanos] is strictly increasing between batches.
  Map<String, int> dstUpdateNanos;
}

/// Some common tag keys
const String kGithubRepoKey = 'gitRepo';
const String kGitRevisionKey = 'gitRevision';
const String kSourceIdKey = 'sourceId';
const String kTaskNameKey = 'taskName';
const String kUnitKey = 'unit';
const String kNameKey = 'name';

/// Some constants
const int kMinTimeNanos = -(1 << 53);

/// Known source/destination ids
const String kCocoonId = 'cocoon';
const String kSkiaPerfId = 'skiaperf';

/// Known github repo
const String kFlutterFrameworkRepo = 'flutter/flutter';
const String kFlutterEngineRepo = 'flutter/engine';
