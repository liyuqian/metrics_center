import 'package:metrics_center/src/common.dart';
import 'package:metrics_center/google_benchmark.dart';
import 'package:test/test.dart';

import 'utility.dart';

void main() {
  test('GoogleBenchmarkParser parses example json.', () async {
    List<MetricPoint> points =
        await GoogleBenchmarkParser.parse('test/example_google_benchmark.json');
    expect(points.length, 6);
    expectSetMatch(
        points.map((p) => p.value), [101, 101, 4460, 4460, 6548, 6548]);
    expectSetMatch(points.map((p) => p.tags[kSubResultKey]),
        ['cpu_time', 'real_time', 'cpu_coefficient', 'real_coefficient']);
    expectSetMatch(points.map((p) => p.tags[kNameKey]), [
      'BM_PaintRecordInit',
      'BM_ParagraphShortLayout',
      'BM_ParagraphStylesBigO_BigO'
    ]);
  });
}
