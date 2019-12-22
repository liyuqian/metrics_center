// Transform the json result of https://github.com/google/benchmark

import 'dart:convert';
import 'dart:io';

import 'package:metrics_center/src/common.dart';

const String _kTimeUnitKey = 'time_unit';

const List<String> _kNonNumericalValueSubResults = <String>[
  kNameKey,
  _kTimeUnitKey,
  'iterations',
  'big_o',
];

class GoogleBenchmarkParser {
  static Future<List<MetricPoint>> parse(String jsonFileName) async {
    final Map<String, dynamic> jsonResult =
        jsonDecode(File(jsonFileName).readAsStringSync());

    final Map<String, dynamic> rawContext = jsonResult['context'];
    final Map<String, String> context = rawContext.map<String, String>(
      (String k, dynamic v) => MapEntry<String, String>(k, v.toString()),
    );
    final List<MetricPoint> points = [];
    for (Map<String, dynamic> item in jsonResult['benchmarks']) {
      _parseAnItem(item, points, context);
    }
    return points;
  }
}

void _parseAnItem(
  Map<String, dynamic> item,
  List<MetricPoint> points,
  Map<String, String> context,
) {
  final String name = item[kNameKey];
  final Map<String, String> timeUnitMap = <String, String>{
    kUnitKey: item[_kTimeUnitKey]
  };
  for (String subResult in item.keys) {
    if (!_kNonNumericalValueSubResults.contains(subResult)) {
      num rawValue;
      try {
        rawValue = item[subResult];
      } catch (e) {
        print('$subResult: ${item[subResult]} (${item[subResult].runtimeType}) '
            'is not a number');
        rethrow;
      }

      final double value = rawValue is int ? rawValue.toDouble() : rawValue;
      points.add(
        MetricPoint(
          value,
          <String, String>{kNameKey: name, kSubResultKey: subResult}
            ..addAll(context)
            ..addAll(
                subResult.endsWith('time') ? timeUnitMap : <String, String>{}),
          kFlutterCenterId,
        ),
      );
    }
  }
}
