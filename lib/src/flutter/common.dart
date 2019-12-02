import 'dart:convert';

import 'package:gcloud/db.dart';
import 'package:gcloud/src/datastore_impl.dart';
import 'package:googleapis_auth/auth.dart';
import 'package:googleapis_auth/auth_io.dart';

import 'package:metrics_center/src/common.dart';

const kSourceTimeMicrosName = 'sourceTimeMicros';

@Kind(name: 'MetricPoint', idType: IdType.String)
class MetricPointModel extends Model {
  @DoubleProperty(required: true, indexed: false)
  double value;

  @StringListProperty()
  List<String> tags;

  @StringProperty(required: true)
  String originId;

  @IntProperty(propertyName: kSourceTimeMicrosName)
  int sourceTimeMicros;

  MetricPointModel({MetricPoint from}) {
    if (from != null) {
      id = from.id;
      value = from.value;
      originId = from.originId;
      // Explicitly set sourceTimeMicros to null because the sourceTimeMicros
      // should be set by FlutterSource, instead of copying from the
      // MetricPoint.
      sourceTimeMicros = null;
      tags = from.tags.keys
          .map((String key) => jsonEncode({key: from.tags[key]}))
          .toList();
    }
  }
}

Future<DatastoreDB> datastoreFromCredentialsJson(
    Map<String, dynamic> json) async {
  final client = await clientViaServiceAccount(
      ServiceAccountCredentials.fromJson(json), DatastoreImpl.SCOPES);
  return DatastoreDB(DatastoreImpl(client, json['project_id']));
}
