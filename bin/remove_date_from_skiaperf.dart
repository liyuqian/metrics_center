// This is a one-time script to remove date option from old json skiaperf files.
// See commit e17a5c6bf4935dbee53a67ae189535914df71eb1 for why we did this.
import 'dart:convert';
import 'dart:io';

import 'package:gcloud/storage.dart';
import 'package:googleapis_auth/auth.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart' show DetailedApiRequestError;

import 'package:metrics_center/src/skiaperf.dart';

Map<String, dynamic> filter(Map<String, dynamic> json) {
  Map<String, dynamic> result = {};
  for (String key in json.keys) {
    if (json[key] is Map<String, dynamic>) {
      result[key] = filter(json[key]);
    } else if (key != 'date') {
      result[key] = json[key];
    }
  }
  return result;
}

Future<void> handleEntry(Bucket bucket, BucketEntry entry) async {
  final Stream<List<int>> stream = bucket.read(entry.name);
  final Stream<int> byteStream = stream.expand((x) => x);
  final Map<String, dynamic> decodedJson =
      jsonDecode(utf8.decode(await byteStream.toList()));
  final filteredJson = filter(decodedJson);
  await bucket.writeBytes(entry.name, utf8.encode(jsonEncode(filteredJson)));
  print('Handled gs://${bucket.bucketName}/${entry.name}');
}

Future<void> main() async {
  final Map<String, dynamic> credentialsJson =
      jsonDecode(File('secret/gcp_credentials.json').readAsStringSync());
  final credentials = ServiceAccountCredentials.fromJson(credentialsJson);

  final client = await clientViaServiceAccount(credentials, Storage.SCOPES);
  final storage = Storage(client, credentialsJson['project_id']);
  final bucketName = SkiaPerfDestination.kTestBucketName;

  final Bucket bucket = storage.bucket(bucketName);

  final Stream<BucketEntry> entries = bucket.list();

  await for (BucketEntry entry in entries) {
    const kRetry = 5;
    for (int retry = 0; retry < kRetry; retry += 1) {
      try {
        await handleEntry(bucket, entry);
        break;
      } catch (e) {
        if (e is DetailedApiRequestError &&
            e.status == 504 &&
            retry < kRetry - 1) {
          continue;
        }
        rethrow;
      }
    }
  }
}
