import 'utility.dart';

import 'package:gcloud/src/datastore_impl.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:test/test.dart';

import 'package:metrics_center/src/common.dart';
import 'package:metrics_center/src/flutter/destination.dart';

const String kTestSourceId = 'test';

void main() {
  test('FlutterDestination update does not crash.', () async {
    FlutterDestination dst = await FlutterDestination.makeFromCredentialsJson(
        getGcpCredentialsJson());
    await dst.update(<MetricPoint>[MetricPoint(1.0, {}, kTestSourceId)]);
  });

  test('FlutterDestination can be updated with an access token.', () async {
    final credentialsJson = getGcpCredentialsJson();
    final client = await clientViaServiceAccount(
      ServiceAccountCredentials.fromJson(credentialsJson),
      DatastoreImpl.SCOPES,
    );
    final String token = client.credentials.accessToken.data;
    FlutterDestination dst = await FlutterDestination.makeFromAccessToken(
      token,
      credentialsJson['project_id'],
    );
    await dst.update(<MetricPoint>[MetricPoint(1.0, {}, kTestSourceId)]);
  });

  test('FlutterEngineMetricPoint works.', () {
    const String gitRevision = 'ca799fa8b2254d09664b78ee80c43b434788d112';
    final simplePoint = FlutterEngineMetricPoint(
      'BM_ParagraphLongLayout',
      287235,
      gitRevision,
    );
    expect(simplePoint.value, equals(287235));
    expect(simplePoint.originId, kFlutterCenterId);
    expect(simplePoint.tags[kGithubRepoKey], kFlutterEngineRepo);
    expect(simplePoint.tags[kGitRevisionKey], gitRevision);
    expect(simplePoint.tags[kNameKey], 'BM_ParagraphLongLayout');

    final detailedPoint = FlutterEngineMetricPoint(
      'BM_ParagraphLongLayout',
      287224,
      'ca799fa8b2254d09664b78ee80c43b434788d112',
      moreTags: {
        'executable': 'txt_benchmarks',
        'sub_result': 'CPU',
        kUnitKey: 'ns',
      },
    );
    expect(detailedPoint.value, equals(287224));
    expect(detailedPoint.tags['executable'], equals('txt_benchmarks'));
    expect(detailedPoint.tags['sub_result'], equals('CPU'));
    expect(detailedPoint.tags[kUnitKey], equals('ns'));
  });
}
