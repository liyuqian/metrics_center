# Overall concepts

- `MetricPoint`: canonical format of metrics
- `MetricSource`: where we can read `MetricPoint` (e.g.,
  cocoon once we implement the translation from cocoon format to `MetricPoint`
  format)
- `MetricDestination`: where we can write `MetricPoint`.
- `FlutterCenter`: the current implementation of metrics center. It has two
  central `MetricSource` and `MetricDestination` known as `FlutterSource` and
  `FlutterDestination`. The `FlutterSource` and `FlutterDestination` share the
  same data so what's written into `FlutterDestination` can be read from
  `FlutterSource`. It also has several other sources and destinations. As a
  center, it can
    - Let benchmarks directly write metrics into the central
       `FlutterDestination`. (Currently done by engine benchmarks.)
    - Automatically pull new metrics from other sources and store them in the
       central `FlutterDestination`. (Will be done by cocoon.)
    - Automatically push new metrics from the central `FlutterSource` into other
       destinations. (Currently done with `SkiaPerfDestination`.)

# How metrics currently flow

## Flutter engine txt_benchmark example

1. Run post-submit test jobs in GKE containers managed by Cirrus. Generate and
   write metrics into the metrics center datastore in the canonical format
   `MetricPoint`. See `build_and_benchmark_linux_release` task in
   "[.cirrus.yml][1]".
   1. Run benchmarks to generate `txt_benchmark.json`
   2. Run "[parse_and_send.dart][2]" to parse `txt_benchmark.json` and turn
      Google benchmarks format into our canonical format `MetricPoint`, and
      write it into a GCP datastore (metrics center datastore).
      - `parse_and_send.dart` relied on `metrics_center` package for format
        translation, GCP authentication, and datastore transactions. See
        "[pubspec.yaml][3]".
      - `MetricPoint` is defined in "[common.dart][4]" of metrics_center
        package.
      - The translation is defined in [GoogleBenchmarksParser][6].
      - GCP authentication is done by providing json crendentials
        ```
        FlutterDestination.makeFromCredentialsJson(someJson)
        ```
        which also specifies which GCP project is used. In Cirrus, we used [an
        environment variable][5] encrypted/decrypted by Cirrus so it's not
        exposed in the open source code.
      - When the translation finished generating `points` and the authentication
        finished generating `destination`, simply call `await
        destination.update(points)` to write `points` into the datastore.

2. Run `FlutterCenter.synchronize` to transform all new metrics from the metrics
   center datastore into Skia perf format, and write them into the GCS bucket
   required by Skia perf.
     - Currently `synchronize` is run from a standalone script
       "[run_flutter_center.dart][7]" in a GCE instance. We plan to move it to a
       GAE handler in cocoon for better logging and error reporting.
     - In `synchronize`, `FlutterCenter` first pulls new metrics from other
       sources and writes them into the metrics center datastore. Currently,
       there's no other source. In the future, we'll make cocoon datastore as
       the other source so `synchronize` would pull data from cocoon,
       translating its format to canonical format `MetricPoint`, and write them
       into the metrics center datastore. (Cocoon datastore and metric center
       datastore can be the same.)
     - Then `FlutterCenter` writes all new `MetricPoint` from the metrics center
       datastore, and push them to other destinations. Currently, there's only
       one other destination `SkiaPerfDestination`. [SkiaPerfDestination][8]
       would do all the translations and adaptations to make sure that Skia perf
       can pick up the metrics.
     - Timestamps are properly managed so only new metrics are synchronized
       without duplications.


[1]: https://github.com/flutter/engine/blob/master/.cirrus.yml
[2]: https://github.com/flutter/engine/blob/master/testing/benchmark/bin/parse_and_send.dart
[3]: https://github.com/flutter/engine/blob/master/testing/benchmark/pubspec.yaml
[4]: https://github.com/liyuqian/metrics_center/blob/master/lib/src/common.dart
[5]: https://github.com/flutter/engine/blob/025e2d82dda54af7f33a0d511bde47ec835593b1/testing/benchmark/bin/parse_and_send.dart#L52
[6]: https://github.com/liyuqian/metrics_center/blob/master/lib/google_benchmark.dart
[7]: https://github.com/liyuqian/metrics_center/blob/master/bin/run_flutter_center.dart
[8]: https://github.com/liyuqian/metrics_center/blob/master/lib/src/skiaperf.dart