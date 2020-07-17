// This is a one-off script to remove unwanted entities from flutter center.
// Feel free to change it as needed.
import 'dart:convert';
import 'dart:io';
import 'package:gcloud/db.dart';
import 'package:metrics_center/src/flutter/common.dart';

Future<void> main(List<String> args) async {
  // As this script is dangerous, this return works as a safeguard.
  // Please remove it before actual execution.
  return;

  final String credentials =
      File('secret/gcp_credentials.json').readAsStringSync();
  final db = await datastoreFromCredentialsJson(jsonDecode(credentials));
  final query = db.query<MetricPointModel>();
  query.filter('originId =', 'devicelab');
  query.limit(500);

  int total = 0;
  while (true) {
    List<Key> keys = [];
    await for (MetricPointModel model in query.run()) {
      keys.add(model.key);
    }
    if (keys.isEmpty) break;
    await db.commit(deletes: keys);
    total += keys.length;
    print('deleted $total keys');
  }
}
