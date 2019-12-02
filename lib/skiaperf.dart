import 'dart:collection';
import 'dart:convert';

import 'package:gcloud/storage.dart';

import 'base.dart';

// Skia Perf Format is a JSON file that looks like:

// {
//     "gitHash": "fe4a4029a080bc955e9588d05a6cd9eb490845d4",
//     "key": {
//         "arch": "x86",
//         "gpu": "GTX660",
//         "model": "ShuttleA",
//         "os": "Ubuntu12"
//     },
//     "results": {
//         "ChunkAlloc_PushPop_640_480": {
//             "nonrendering": {
//                 "min_ms": 0.01485466666666667,
//                 "options": {
//                     "source_type": "bench"
//                 }
//             }
//         },
//         "DeferredSurfaceCopy_discardable_640_480": {
//             "565": {
//                 "min_ms": 2.215988,
//                 "options": {
//                     "source_type": "bench"
//                 }
//             },
//     ...

class SkiaPoint extends Point {
  SkiaPoint(this.gitRepo, this.gitHash, this.value, this._options, this.jsonUrl)
      : tags = SplayTreeMap.from(_options) {
    tags[kGitRepoKey] = gitRepo;
    tags[kGitRevisionKey] = gitHash;

    assert(tags[kGitRepoKey] != null);
    assert(tags[kGitRevisionKey] != null);
    assert(tags[kNameKey] != null);
    assert(_options[kGitRepoKey] == null);
    assert(_options[kGitRevisionKey] == null);
  }

  factory SkiaPoint.fromPoint(Point p) {
    final String gitRepo = p.tags[kGitRepoKey];
    final String gitHash = p.tags[kGitRevisionKey];
    if (gitRepo == null || gitHash == null) {
      return null;
    }

    if (p.tags[kNameKey] == null) {
      return null;
    }

    final Map<String, String> optionsWithSourceId = {}..addEntries(
        p.tags.entries.where(
          (MapEntry<String, dynamic> entry) =>
              entry.key != kGitRepoKey && entry.key != kGitRevisionKey,
        ),
      );

    // Map<String, String> optionsWithSourceId = p.tags.wh;
    if (optionsWithSourceId[kSourceIdKey] == null) {
      optionsWithSourceId[kSourceIdKey] = p.sourceId;
    }

    assert(optionsWithSourceId[kSourceIdKey] == p.sourceId);

    return SkiaPoint(gitRepo, gitHash, p.value, optionsWithSourceId, null);
  }

  @override
  final double value;

  @override
  final SplayTreeMap<String, String> tags;

  /// If the source id is not specified in tags, we'll consider this as the
  /// original data from Skia perf.
  @override
  String get sourceId => tags[kSourceIdKey] ?? 'perf.skia.org';

  @override
  int get updateTimeNanos => gsFileModifiedTimeNanos(jsonUrl);

  final String gitRepo;
  final String gitHash;

  String get name => tags[kNameKey];

  final String jsonUrl;

  Map<String, dynamic> _toSubResultJson() {
    return <String, dynamic>{
      kSkiaPerfValueKey: value,
      kSkiaPerfOptionsKey: _options,
    };
  }

  /// Convert a list of SkiaPoints with the same git repo and git revision into
  /// a single json file in the Skia perf format.
  ///
  /// The list must be non-empty.
  static Map<String, dynamic> toSkiaPerfJson(List<SkiaPoint> points) {
    assert(points.length > 0);
    assert(() {
      for (SkiaPoint p in points) {
        if (p.gitRepo != points[0].gitRepo || p.gitHash != points[0].gitHash) {
          return false;
        }
      }
      return true;
    }(), 'All points must have same gitRepo and gitHash');

    final results = <String, dynamic>{};
    for (SkiaPoint p in points) {
      results[p.name] = p._toSubResultJson();
    }

    return <String, dynamic>{
      kSkiaPerfGitHashKey: points[0].gitHash,
      kSkiaPerfResultsKey: results,
    };
  }

  // Equivalent to tags without git repo and git hash because those two are
  // stored in the GCS object name.
  final Map<String, dynamic> _options;
}

class SkiaPerfDestination extends MetricsDestination {
  SkiaPerfDestination(this._gcs);

  @override
  String get id => kSkiaPerfId;

  @override
  Future<void> update(Iterable<Point> points) async {
    // 1st, create a map based on git repo, git revision, and point id. Git repo
    // and git revision are the top level components of the Skia perf GCS object
    // name.
    final Map<String, Map<String, Map<String, SkiaPoint>>> pointMap = {};
    for (SkiaPoint p in points.map((x) => SkiaPoint.fromPoint(x))) {
      if (p != null) {
        pointMap[p.gitRepo] ??= {};
        pointMap[p.gitRepo][p.gitHash] ??= {};
        pointMap[p.gitRepo][p.gitHash][p.id] = p;
      }
    }

    // 2nd, read existing points from the gcs object and update with new ones.
    for (String repo in pointMap.keys) {
      for (String revision in pointMap[repo].keys) {
        final String objectName = SkiaPerfGcsAdaptor.comptueObjectName(repo, revision);
        final Map<String, SkiaPoint> newPoints = pointMap[repo][revision];
        final List<SkiaPoint> oldPoints = await _gcs.readPoints(objectName);
        for (SkiaPoint p in oldPoints) {
          if (newPoints[p.id] == null) {
            newPoints[p.id] = p;
          }
        }
        await _gcs.writePoints(objectName, newPoints.values);
      }
    }
  }

  final SkiaPerfGcsAdaptor _gcs;
}

class SkiaPerfGcsAdaptor {
  SkiaPerfGcsAdaptor(this._gcsBucket) : assert(_gcsBucket != null);

  // Used by Skia to differentiate json file format versions.
  static const int version = 1;

  Future<void> writePoints(
      String objectName, Iterable<SkiaPoint> points) async {
    String jsonString = jsonEncode(SkiaPoint.toSkiaPerfJson(points));
    _gcsBucket.writeBytes(objectName, utf8.encode(jsonString));
  }

  // Return an  empty list if the object does not exist in the GCS bucket.
  Future<List<SkiaPoint>> readPoints(String objectName) async {
    final Stream<List<int>> stream = _gcsBucket.read(objectName);
    final Stream<int> byteStream = stream.expand((x) => x);
    final Map<String, dynamic> decodedJson =
        jsonDecode(utf8.decode(await byteStream.toList()));

    final List<SkiaPoint> points = [];

    final String firstGcsNameComponent = objectName.split('/')[0];
    _populateGcsNameToGitRepoMapIfNeeded();
    final String gitRepo = _gcsNameToGitRepo[firstGcsNameComponent];
    assert(gitRepo != null);

    final String gitHash = decodedJson[kSkiaPerfGitHashKey];
    Map<String, dynamic> results = decodedJson[kSkiaPerfResultsKey];
    for (String name in results.keys) {
      final Map<String, dynamic> subResult = results[name];
      // TODO(liyuqian): set jsonUrl and updateTimeNanos
      points.add(SkiaPoint(
        gitRepo,
        gitHash,
        subResult[kSkiaPerfValueKey],
        subResult[kSkiaPerfOptionsKey],
        null,
      ));
    }
    return points;
  }

  static String comptueObjectName(String repo, String revision) {
    return '${_gitRepoToGcsName[repo]}/$revision/values.json';
    // TODO: implement
  }

  static final Map<String, String> _gitRepoToGcsName = {
    kFlutterFrameworkRepo: 'flutter-flutter',
    kFlutterEngineRepo: 'flutter-engine',
  };
  static final Map<String, String> _gcsNameToGitRepo = {};

  static void _populateGcsNameToGitRepoMapIfNeeded() {
    if (_gcsNameToGitRepo.isEmpty) {
      for (String repo in _gitRepoToGcsName.keys) {
        final String gcsName = _gitRepoToGcsName[repo];
        assert(_gcsNameToGitRepo[gcsName] == null);
        _gcsNameToGitRepo[gcsName] = repo;
      }
    }
  }

  Bucket _gcsBucket;
}

int gsFileModifiedTimeNanos(String url) {
  // throw UnimplementedError();
  return null;
}

String gsFileRead(String url) {
  // throw UnimplementedError();
  return null;
}

const String kSkiaPerfGitHashKey = 'gitHash';
const String kSkiaPerfResultsKey = 'results';
const String kSkiaPerfValueKey = 'value';
const String kSkiaPerfOptionsKey = 'options';
