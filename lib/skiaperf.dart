import 'dart:collection';

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
  SkiaPoint(this.value, this.tags, this.jsonUrl) {
    assert(tags[kGitRepoKey] != null);
    assert(tags[kGitRevisionKey] != null);
    assert(tags[kNameKey] != null);

    _options.addEntries(
      tags.entries.where(
        (MapEntry<String, dynamic> entry) =>
            entry.key != kGitRevisionKey && entry.key != kGitRevisionKey,
      ),
    );
  }

  factory SkiaPoint.fromPoint(Point p) {
    if (p.tags[kGitRevisionKey] == null || p.tags[kGitRepoKey] == null) {
      return null;
    }

    if (p.tags[kNameKey] == null) {
      return null;
    }

    SplayTreeMap<String, String> tagsWithSourceId = p.tags;
    if (tagsWithSourceId[kSourceIdKey] == null) {
      tagsWithSourceId = SplayTreeMap.from(p.tags);
      tagsWithSourceId[kSourceIdKey] = p.sourceId;
    }

    assert(tagsWithSourceId[kSourceIdKey] == p.sourceId);

    return SkiaPoint(p.value, tagsWithSourceId, null);
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

  String get gitRepo => tags[kGitRepoKey];
  String get gitHash => tags[kGitRevisionKey];
  String get name => tags[kNameKey];

  final String jsonUrl;

  Map<String, dynamic> toSkiaPerfJson() {
    return <String, dynamic>{
      kSkiaPerfGitHashKey: gitHash,
      kSkiaPerfResultsKey: <String, dynamic>{
        name: <String, dynamic>{
          'value': value,
          'options': _options,
        },
      },
    };
  }

  // Equivalent to tags without git hash and git repo.
  final Map<String, dynamic> _options = {};
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
        final String objectName = _gcs.comptueObjectName(repo, revision);
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
  Future<void> writePoints(
      String objectName, Iterable<SkiaPoint> points) async {
    // TODO implememnt
  }

  // Return an  empty list if the object does not exist in the GCS bucket.
  Future<List<SkiaPoint>> readPoints(String objectName) async {
    // TODO implememt
    return [];
  }

  String comptueObjectName(String repo, String revision) {
    // TODO: implement
    return null;
  }

  Bucket _gcsBucket;

  // Used by Skia to differentiate json file format versions.
  static const int version = 1;
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
