import 'dart:convert';

import 'package:gcloud/storage.dart';
import 'package:googleapis_auth/auth.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:metrics_center/src/github_helper.dart';

import 'package:metrics_center/src/common.dart';

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

class SkiaPerfPoint extends MetricPoint {
  SkiaPerfPoint._(this.githubRepo, this.gitHash, this.name, this._subResult,
      double value, this._options, this.jsonUrl, DateTime sourceTime)
      : super(
          value,
          {}
            ..addAll(_options)
            ..addAll({
              kGithubRepoKey: githubRepo,
              kGitRevisionKey: gitHash,
              kNameKey: name,
              kSubResultKey: _subResult,
            }),
          _options[kOriginIdKey] ?? kSkiaPerfId,
          sourceTime,
        ) {
    assert(tags[kGithubRepoKey] != null);
    assert(tags[kGitRevisionKey] != null);
    assert(tags[kNameKey] != null);
    assert(_options[kGithubRepoKey] == null);
    assert(_options[kGitRevisionKey] == null);
    assert(_options[kNameKey] == null);
  }

  factory SkiaPerfPoint.fromPoint(MetricPoint p) {
    final String githubRepo = p.tags[kGithubRepoKey];
    final String gitHash = p.tags[kGitRevisionKey];
    final String name = p.tags[kNameKey];
    final String subResult = p.tags[kSubResultKey] ?? kSkiaPerfValueKey;

    if (githubRepo == null || gitHash == null || name == null) {
      return null;
    }

    final Map<String, String> optionsWithSourceId = {}..addEntries(
        p.tags.entries.where(
          (MapEntry<String, dynamic> entry) =>
              entry.key != kGithubRepoKey &&
              entry.key != kGitRevisionKey &&
              entry.key != kNameKey &&
              entry.key != kSubResultKey,
        ),
      );

    if (optionsWithSourceId[kOriginIdKey] == null) {
      optionsWithSourceId[kOriginIdKey] = p.originId;
    }

    assert(optionsWithSourceId[kOriginIdKey] == p.originId);

    return SkiaPerfPoint._(githubRepo, gitHash, name, subResult, p.value,
        optionsWithSourceId, null, null);
  }

  /// In the format of '<owner>/<name>' such as 'flutter/flutter' or
  /// 'flutter/engine'.
  final String githubRepo;

  /// SHA such as 'ad20d368ffa09559754e4b2b5c12951341ca3b2d'
  final String gitHash;

  final String name;

  // The name of "subResult" comes from the special treatment of "sub_result" in
  // SkiaPerf. If not provided, its value will be set to kSkiaPerfValueKey.
  final String _subResult;

  /// The url to the Skia perf json file in the Google Cloud Storage bucket.
  ///
  /// This can be null if the point has been stored in the bucket yet.
  final String jsonUrl;

  Map<String, dynamic> _toSubResultJson() {
    return <String, dynamic>{
      _subResult: value,
      kSkiaPerfOptionsKey: _options,
    };
  }

  /// Convert a list of SkiaPoints with the same git repo and git revision into
  /// a single json file in the Skia perf format.
  ///
  /// The list must be non-empty.
  static Map<String, dynamic> toSkiaPerfJson(List<SkiaPerfPoint> points) {
    assert(points.isNotEmpty);
    assert(() {
      for (SkiaPerfPoint p in points) {
        if (p.githubRepo != points[0].githubRepo ||
            p.gitHash != points[0].gitHash) {
          return false;
        }
      }
      return true;
    }(), 'All points must have same githubRepo and gitHash');

    final results = <String, dynamic>{};
    for (SkiaPerfPoint p in points) {
      final Map<String, dynamic> subResultJson = p._toSubResultJson();
      if (results[p.name] == null) {
        results[p.name] = {
          kSkiaPerfDefaultConfig: subResultJson,
        };
      } else {
        // Flutter currently does't support having the same name but different
        // options/configurations. If this actually happens in the future, we
        // probably can use different values of config (currently there's only
        // one kSkiaPerfDefaultConfig) to resolve the conflict.
        assert(results[p.name][kSkiaPerfDefaultConfig][kSkiaPerfOptionsKey]
                .toString() ==
            subResultJson[kSkiaPerfOptionsKey].toString());
        assert(results[p.name][kSkiaPerfDefaultConfig][p._subResult] == null);
        results[p.name][kSkiaPerfDefaultConfig][p._subResult] = p.value;
      }
    }

    return <String, dynamic>{
      kSkiaPerfGitHashKey: points[0].gitHash,
      kSkiaPerfResultsKey: results,
    };
  }

  // Equivalent to tags without git repo, git hash, and name because those two
  // are already stored somewhere else.
  final Map<String, dynamic> _options;
}

class SkiaPerfDestination extends MetricDestination {
  static const String kBucketName = 'flutter-skia-perf';
  static const String kTestBucketName = 'flutter-skia-perf-test';

  static Future<SkiaPerfDestination> makeFromGcpCredentials(
      Map<String, dynamic> credentialsJson,
      {bool isTesting = false}) async {
    final credentials = ServiceAccountCredentials.fromJson(credentialsJson);

    final client = await clientViaServiceAccount(credentials, Storage.SCOPES);
    final storage = Storage(client, credentialsJson['project_id']);
    final bucketName = isTesting ? kTestBucketName : kBucketName;

    if (!await storage.bucketExists(bucketName)) {
      throw 'Bucket $kBucketName does not exist.';
    }

    return SkiaPerfDestination(SkiaPerfGcsAdaptor(storage.bucket(bucketName)));
  }

  SkiaPerfDestination(this._gcs);

  @override
  String get id => kSkiaPerfId;

  @override
  Future<void> update(List<MetricPoint> points) async {
    // 1st, create a map based on git repo, git revision, and point id. Git repo
    // and git revision are the top level components of the Skia perf GCS object
    // name.
    final Map<String, Map<String, Map<String, SkiaPerfPoint>>> pointMap = {};
    for (SkiaPerfPoint p in points.map((x) => SkiaPerfPoint.fromPoint(x))) {
      if (p != null) {
        pointMap[p.githubRepo] ??= {};
        pointMap[p.githubRepo][p.gitHash] ??= {};
        pointMap[p.githubRepo][p.gitHash][p.id] = p;
      }
    }

    // 2nd, read existing points from the gcs object and update with new ones.
    for (String repo in pointMap.keys) {
      for (String revision in pointMap[repo].keys) {
        final String objectName =
            await SkiaPerfGcsAdaptor.comptueObjectName(repo, revision);
        final Map<String, SkiaPerfPoint> newPoints = pointMap[repo][revision];
        final List<SkiaPerfPoint> oldPoints = await _gcs.readPoints(objectName);
        for (SkiaPerfPoint p in oldPoints) {
          if (newPoints[p.id] == null) {
            newPoints[p.id] = p;
          }
        }
        await _gcs.writePoints(objectName, newPoints.values.toList());
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
      String objectName, List<SkiaPerfPoint> points) async {
    String jsonString = jsonEncode(SkiaPerfPoint.toSkiaPerfJson(points));
    await _gcsBucket.writeBytes(objectName, utf8.encode(jsonString));
  }

  // Return an  empty list if the object does not exist in the GCS bucket.
  Future<List<SkiaPerfPoint>> readPoints(String objectName) async {
    ObjectInfo info;

    // Retry multiple times as GCS may return 504 timeout.
    for (int retry = 0; true; retry += 1) {
      try {
        info = await _gcsBucket.info(objectName);
        break;
      } catch (e) {
        if (e.toString().contains('No such object')) {
          return [];
        } else {
          if (retry == 5) {
            rethrow;
          }
        }
      }
    }
    final Stream<List<int>> stream = _gcsBucket.read(objectName);
    final Stream<int> byteStream = stream.expand((x) => x);
    final Map<String, dynamic> decodedJson =
        jsonDecode(utf8.decode(await byteStream.toList()));

    final List<SkiaPerfPoint> points = [];

    final String firstGcsNameComponent = objectName.split('/')[0];
    _populateGcsNameToGithubRepoMapIfNeeded();
    final String githubRepo = _gcsNameToGithubRepo[firstGcsNameComponent];
    assert(githubRepo != null);

    final String gitHash = decodedJson[kSkiaPerfGitHashKey];
    Map<String, dynamic> results = decodedJson[kSkiaPerfResultsKey];
    for (String name in results.keys) {
      final Map<String, dynamic> subResultMap =
          results[name][kSkiaPerfDefaultConfig];
      for (String subResult in subResultMap.keys.where((s) => s != kSkiaPerfOptionsKey)) {
        points.add(SkiaPerfPoint._(
          githubRepo,
          gitHash,
          name,
          subResult,
          subResultMap[subResult],
          subResultMap[kSkiaPerfOptionsKey],
          info.downloadLink.toString(),
          info.updated,
        ));
      }
    }
    return points;
  }

  static Future<String> comptueObjectName(
      String githubRepo, String revision) async {
    assert(_githubRepoToGcsName[githubRepo] != null);
    final String topComponent = _githubRepoToGcsName[githubRepo];
    final DateTime t =
        await GithubHelper().getCommitDateTime(githubRepo, revision);
    final String hour = t.hour.toString().padLeft(2, '0');
    final String dateComponents = '${t.year}/${t.month}/${t.day}/$hour';
    return '$topComponent/$dateComponents/$revision/values.json';
  }

  static final Map<String, String> _githubRepoToGcsName = {
    kFlutterFrameworkRepo: 'flutter-flutter',
    kFlutterEngineRepo: 'flutter-engine',
  };
  static final Map<String, String> _gcsNameToGithubRepo = {};

  static void _populateGcsNameToGithubRepoMapIfNeeded() {
    if (_gcsNameToGithubRepo.isEmpty) {
      for (String repo in _githubRepoToGcsName.keys) {
        final String gcsName = _githubRepoToGcsName[repo];
        assert(_gcsNameToGithubRepo[gcsName] == null);
        _gcsNameToGithubRepo[gcsName] = repo;
      }
    }
  }

  Bucket _gcsBucket;
}

const String kSkiaPerfGitHashKey = 'gitHash';
const String kSkiaPerfResultsKey = 'results';
const String kSkiaPerfValueKey = 'value';
const String kSkiaPerfOptionsKey = 'options';

const String kSkiaPerfDefaultConfig = 'default';
