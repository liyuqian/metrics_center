import 'dart:collection';

/// Common format of a metric data point
class MetricPoint {
  MetricPoint(
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

  /// The last modified time of this point in a [MetricSource]. Can be null if
  /// this point isn't loaded from a source (e.g., it's constructed in memory).
  final DateTime sourceTime;

  final SplayTreeMap<String, String> _tags;
}

/// Source must support efficient index on [MetricPoint.sourceTime]
/// so we can query with a time range.
abstract class MetricSource<SourcePoint extends MetricPoint> {
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

abstract class MetricDestination {
  /// Insert new data points or modify old ones with matching id.
  ///
  /// Deletion is done by setting [MetricPoint.value] to [double.nan].
  ///
  /// The destination could also ignore some points and not store them. For the
  /// non-ignored points, it should faithfully store the value, tags, raw, and
  /// originId fields. Thus, if this destination is also a source (e.g., a
  /// [MetricsCenter]), then when [getUpdatesAfter] is called on the source, we
  /// should get the points with exactly the same fields that we just updated.
  /// This is especially important for the originId field which is used for
  /// dedup. Otherwise, there might be an update loop to generate an infinite
  /// amount of duplicate points.
  Future<void> update(List<MetricPoint> points);

  /// Unique id of the destination. If this destination is also a source, then
  /// its corresponding destination (often the same object, e.g.,
  /// [MetricsCenter]) should have the same id.
  String get id;
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
