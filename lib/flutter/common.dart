import 'dart:convert';

import 'package:gcloud/db.dart';
import 'package:gcloud/src/datastore_impl.dart';
import 'package:googleapis_auth/auth.dart';
import 'package:googleapis_auth/auth_io.dart';

import '../common.dart';

const kSourceTimeMicrosName = 'sourceTimeMicros';

@Kind(name: 'FlutterCenterPoint', idType: IdType.String)
class FlutterCenterPoint extends Model {
  @DoubleProperty(required: true, indexed: false)
  double value;

  @StringListProperty()
  List<String> tags;

  @StringProperty(required: true)
  String originId;

  @IntProperty(propertyName: kSourceTimeMicrosName)
  int sourceTimeMicros;

  FlutterCenterPoint({MetricPoint from}) {
    if (from != null) {
      id = from.id;
      value = from.value;
      originId = from.originId;
      sourceTimeMicros = from.sourceTime?.microsecondsSinceEpoch;
      tags = from.tags.keys
          .map((String key) => jsonEncode({key: from.tags[key]}))
          .toList();
    }
  }
}

class DatastoreAdaptor {
  /// The projectId will be inferred from the credentials json.
  static Future<DatastoreAdaptor> makeFromCredentialsJson(
      Map<String, dynamic> json) async {
    final client = await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(json), DatastoreImpl.SCOPES);
    final projectId = json['project_id'];
    return DatastoreAdaptor._(
        DatastoreDB(DatastoreImpl(client, projectId)), projectId);
  }

  final String projectId;
  final DatastoreDB db;

  DatastoreAdaptor._(this.db, this.projectId);
}
