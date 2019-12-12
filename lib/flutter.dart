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
    Map<String, dynamic> json, {
    bool insertOnly = false,
    String datasetId = 'flutter_metrics_center',
    String tableId = 'main',
  }) async {
    final bq = BigqueryApi(await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(json),
        insertOnly
            ? [BigqueryApi.BigqueryInsertdataScope]
            : [BigqueryApi.BigqueryScope]));
    return BigQueryAdaptor._(bq, json['project_id'], datasetId, tableId);
  }

  final String projectId;
  final String datasetId;
  final String tableId;
  final BigqueryApi bq;

  BigQueryAdaptor._(this.bq, this.projectId, this.datasetId, this.tableId);
}

class FlutterDestination extends MetricsDestination {
  static Future<FlutterDestination> makeFromCredentialsJson(
      Map<String, dynamic> json) async {
    final adaptor =
        await BigQueryAdaptor.makeFromCredentialsJson(json, insertOnly: true);
    return FlutterDestination._(adaptor);
  }

  @override
  String get id => kFlutterCenterId;

  @override
  Future<void> update(Iterable<Point> points) async {
    final rows = <TableDataInsertAllRequestRows>[];

    for (Point p in points) {
      rows.add(
        TableDataInsertAllRequestRows()
          ..insertId = p.id
          ..json = JsonObject.fromJson({
            kValueColName: p.value,
            kTagsColName: p.tags.keys
                .map((String key) => jsonEncode({key: p.tags[key]}))
                .toList(),
            kSourceIdColName: p.sourceId,
            // TODO: set the srcTimeNanos to now instead of copying from the old source.
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

    if (response.insertErrors != null && response.insertErrors.isNotEmpty) {
      throw InsertError(response.insertErrors);
    }

    // TODO: check that the write actually is successful as the BigQuery may sildently
    // fail to insert rows.
  }

  FlutterDestination._(this._adaptor);

  final BigQueryAdaptor _adaptor;
}

class FlutterCenter extends MetricsCenter {
  @override
  Future<Iterable<BasePoint>> getUpdatesAfter(int timeNanos) async {
    final request = QueryRequest()
      ..query = '''
        SELECT $_cols FROM `$_fullTableName`
        WHERE $kSrcTimeNanosColName > $timeNanos
        ORDER BY $kSrcTimeNanosColName ASC
      '''
      ..useLegacySql = false;
    QueryResponse response =
        await _adaptor.bq.jobs.query(request, _adaptor.projectId);

    // TODO(liyuqian): handle response errors
    assert(response.errors == null || response.errors.isEmpty);

    // The rows can be null if the query has no matched rows
    if (response.rows == null) {
      return [];
    }

    final points = <BasePoint>[];
    for (TableRow row in response.rows) {
      final value = double.parse(row.f[0].v);
      final String sourceId = row.f[2].v;
      final srcTimeNanos = int.parse(row.f[3].v);

      final Map<String, String> tags = {};
      for (Map<String, dynamic> entry in row.f[1].v) {
        final Map<String, dynamic> singleTag = jsonDecode(entry['v']);
        assert(singleTag.length == 1);
        tags[singleTag.keys.elementAt(0)] = singleTag.values.elementAt(0);
      }

      points.add(BasePoint(value, tags, sourceId, srcTimeNanos));
    }
    return points;
  }

  @override
  String get id => kFlutterCenterId;

  @override
  Future<void> update(Iterable<Point> points) async {
    await _internalDst.update(points);
  }

  Future<void> createTableIfNeeded() async {
    try {
      await _adaptor.bq.datasets.get(_adaptor.projectId, _adaptor.datasetId);
    } on DetailedApiRequestError catch (e) {
      if (e.message.contains('Not found: Dataset')) {
        final datasetRef = DatasetReference()..datasetId = _adaptor.datasetId;
        await _adaptor.bq.datasets.insert(
            Dataset()..datasetReference = datasetRef, _adaptor.projectId);
      } else {
        throw e;
      }
    }

    try {
      await _adaptor.bq.tables
          .get(_adaptor.projectId, _adaptor.datasetId, _adaptor.tableId);
    } on DetailedApiRequestError catch (e) {
      if (e.message.contains('Not found: Table')) {
        final Table table = Table();
        table.tableReference = TableReference()..tableId = _adaptor.tableId;

        table.schema = TableSchema()
          ..fields = <TableFieldSchema>[
            TableFieldSchema()
              ..name = kValueColName
              ..type = 'FLOAT'
              ..mode = 'REQUIRED',
            TableFieldSchema()
              ..name = kTagsColName
              ..type = 'STRING'
              ..mode = 'REPEATED',
            TableFieldSchema()
              ..name = kSourceIdColName
              ..type = 'STRING'
              ..mode = 'REQUIRED',
            TableFieldSchema()
              ..name = kSrcTimeNanosColName
              ..type = 'INTEGER'
              ..mode = 'REQUIRED',
          ];

        await _adaptor.bq.tables
            .insert(table, _adaptor.projectId, _adaptor.datasetId);
      } else {
        throw e;
      }
    }
  }

  static Future<FlutterCenter> makeFromCredentialsJson(
      Map<String, dynamic> json) async {
    final adaptor = await BigQueryAdaptor.makeFromCredentialsJson(json);
    return FlutterCenter._(adaptor);
  }

  // TODO(liyuqian): also construct with src and dst list
  FlutterCenter._(this._adaptor)
      : _internalDst = FlutterDestination._(_adaptor);

  final FlutterDestination _internalDst;

  final BigQueryAdaptor _adaptor;

  String get _fullTableName =>
      '${_adaptor.projectId}.${_adaptor.datasetId}.${_adaptor.tableId}';

  String get _cols =>
      '$kValueColName, $kTagsColName, $kSourceIdKey, $kSrcTimeNanosColName';
}

class InsertError extends Error {
  InsertError(this.actualErrors);

  final List<TableDataInsertAllResponseInsertErrors> actualErrors;

  @override
  String toString() {
    return 'InsertError: ${actualErrors.map((e) => e.toJson())}';
  }
}
