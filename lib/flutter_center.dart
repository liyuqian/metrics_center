import 'dart:convert';

import 'package:googleapis/bigquery/v2.dart';
import 'package:googleapis_auth/auth.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:metrics_center/base.dart';

const kValueColName = 'value';
const kTagsColName = 'tags';
const kSourceIdColName = 'sourceId';
const kSrcTimeNanosColName = 'srcTimeNanos';

class BigQueryConfig {
  const BigQueryConfig(this.projectId, this.datasetId, this.tableId);

  final String projectId;
  final String datasetId;
  final String tableId;
}

// TODO(liyuqian): config
const BigQueryConfig defaultConfig = BigQueryConfig('', '', '');

class FlutterMetricsDestination extends MetricsDestination {
  static Future<FlutterMetricsDestination> makeFromCredentialsJson(
    String json, {
    BigQueryConfig config = defaultConfig,
  }) async {
    final bq = BigqueryApi(
      await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(json),
        [BigqueryApi.BigqueryInsertdataScope],
      ),
    );
    return FlutterMetricsDestination._(bq, config);
  }

  @override
  String get id => kFlutterCenterId;

  @override
  Future<void> update(Iterable<Point> points) async {
    final rows = <TableDataInsertAllRequestRows>[];

    for (Point p in points) {
      rows.add(
        TableDataInsertAllRequestRows()
          ..json = JsonObject.fromJson({
            kValueColName: p.value,
            kTagsColName: p.tags.keys
                .map((String key) => jsonEncode({key: p.tags[key]}))
                .toList(),
            kSourceIdColName: p.sourceId,
            kSrcTimeNanosColName: p.srcTimeNanos,
          }),
      );
    }

    final TableDataInsertAllResponse response = await _bq.tabledata.insertAll(
      TableDataInsertAllRequest()..rows = rows,
      _config.projectId,
      _config.datasetId,
      _config.tableId,
    );

    // TODO(liyuqian): Handle failure more elegantly
    for (TableDataInsertAllResponseInsertErrors error
        in response.insertErrors) {
      throw error;
    }
  }

  FlutterMetricsDestination._(this._bq, this._config);

  final BigqueryApi _bq;
  final BigQueryConfig _config;
}

class FlutterMetricsCenter extends MetricsCenter {
  @override
  Future<Iterable<BasePoint>> getUpdatesAfter(int timeNanos) {
    // TODO: implement getUpdatesAfter
    return null;
  }

  @override
  String get id => kFlutterCenterId;

  @override
  Future<void> update(Iterable<Point> points) async {
    await _internalDst.update(points);
  }

  // TODO(liyuqian): also construct with src and dst list
  FlutterMetricsCenter._(this._bq, this._config)
      : _internalDst = FlutterMetricsDestination._(_bq, _config);

  final FlutterMetricsDestination _internalDst;

  final BigqueryApi _bq;
  final BigQueryConfig _config;
}

Future<int> x() async {
  return 1;
}
