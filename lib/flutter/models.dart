import 'dart:convert';

import 'package:gcloud/db.dart';

import '../base.dart';

const kSourceTimeMicrosName = 'sourceTimeMicros';

@Kind(name: 'FlutterCenterPoint', idType: IdType.String)
class FlutterCenterPoint extends Model {
  @DoubleProperty(required: true, indexed: false)
  double value;

  @StringListProperty()
  List<String> tags;

  @StringProperty(required: true)
  String sourceId;

  @IntProperty(propertyName: kSourceTimeMicrosName)
  int sourceTimeMicros;

  FlutterCenterPoint({Point from}) {
    if (from != null) {
      id = from.id;
      value = from.value;
      sourceId = from.sourceId;
      sourceTimeMicros = from.sourceTime?.microsecondsSinceEpoch;
      tags = from.tags.keys
          .map((String key) => jsonEncode({key: from.tags[key]}))
          .toList();
    }
  }
}
