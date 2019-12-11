import 'dart:convert';

import 'package:googleapis/bigquery/v2.dart';
import 'package:googleapis_auth/auth.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:metrics_center/base.dart';

import 'base.dart';

const kValueColName = 'value';
const kTagsColName = 'tags';
const kSourceIdColName = 'sourceId';
const kSrcTimeNanosColName = 'srcTimeNanos';

class BigQueryAdaptor {
  /// The projectId will be inferred from the credentials json.
  static Future<BigQueryAdaptor> makeFromCredentialsJson(
    Map<String, dynamic> json,
    List<String> scopes, {
    String datasetId = kFlutterCenterId,
    String tableId = kFlutterCenterId,
  }) async {
    final bq = BigqueryApi(await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(json), scopes));
    return BigQueryAdaptor._(
        bq, json['project_id'], datasetId, tableId);
  }

  final String projectId;
  final String datasetId;
  final String tableId;
  final BigqueryApi bq;

  BigQueryAdaptor._(this.bq, this.projectId, this.datasetId, this.tableId);
}

class FlutterDestination extends MetricsDestination {
  FlutterDestination(this._adaptor);

  static Future<FlutterDestination> makeFromCredentialsJson(
    Map<String, dynamic> json, {
    String datasetId = kFlutterCenterId,
    String tableId = kFlutterCenterId,
  }) async {
    final adaptor = await BigQueryAdaptor.makeFromCredentialsJson(
        json, [BigqueryApi.BigqueryInsertdataScope],
        datasetId: datasetId, tableId: tableId);
    return FlutterDestination(adaptor);
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

    final TableDataInsertAllResponse response =
        await _adaptor.bq.tabledata.insertAll(
      TableDataInsertAllRequest()..rows = rows,
      _adaptor.projectId,
      _adaptor.datasetId,
      _adaptor.tableId,
    );

    if (response.insertErrors.isNotEmpty) {
      throw InsertError(response.insertErrors);
    }
  }

  final BigQueryAdaptor _adaptor;
}

class FlutterCenter extends MetricsCenter {
  @override
  Future<Iterable<BasePoint>> getUpdatesAfter(int timeNanos) async {
    final request = QueryRequest()
      ..query = 'SELECT $_cols FROM $_fullTableName';
    QueryResponse response =
        await _adaptor.bq.jobs.query(request, _adaptor.projectId);
    // TODO(liyuqian): handle response errors
    final points = <BasePoint>[];
    for (TableRow row in response.rows) {
      points.add(BasePoint(row.f[0].v, row.f[1].v, row.f[2].v, row.f[3].v));
    }
    return points;
  }

  @override
  String get id => kFlutterCenterId;

  @override
  Future<void> update(Iterable<Point> points) async {
    await _internalDst.update(points);
  }

  // TODO(liyuqian): also construct with src and dst list
  FlutterCenter(this._adaptor) : _internalDst = FlutterDestination(_adaptor);

  final FlutterDestination _internalDst;

  final BigQueryAdaptor _adaptor;

  String get _fullTableName =>
      '${_adaptor.projectId}:${_adaptor.datasetId}.${_adaptor.tableId}';

  String get _cols =>
      '$kValueColName, $kTagsColName, $kSourceIdKey $kSrcTimeNanosColName';
}

class InsertError extends Error {
  InsertError(this.actualErrors);

  final List<TableDataInsertAllResponseInsertErrors> actualErrors;
}
