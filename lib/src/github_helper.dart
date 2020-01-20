import 'package:github/github.dart';

class GithubHelper {
  /// Return the singleton helper.
  factory GithubHelper() {
    return _singleton;
  }

  /// The result is cached in memory so querying the same thing again in the
  /// same process is fast.
  Future<DateTime> getCommitDateTime(String githubRepo, String sha) async {
    final String key = '$githubRepo/commit/$sha';
    if (_commitDateTimeCache[key] == null) {
      final RepositoryCommit commit = await _github.repositories
          .getCommit(RepositorySlug.full(githubRepo), sha);
      _commitDateTimeCache[key] = commit.commit.committer.date;
    }
    return _commitDateTimeCache[key];
  }

  GithubHelper._internal();

  static final _singleton = GithubHelper._internal();

  GitHub _github = GitHub();
  Map<String, DateTime> _commitDateTimeCache = {};
}
