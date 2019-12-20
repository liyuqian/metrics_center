// Executable that sets up the center and periodically synchronize.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:metrics_center/src/flutter/center.dart';

const Duration kSleepDuration = Duration(minutes: 30);

const String kTestingFlag = 'testing';

Future<void> main(List<String> args) async {
  final parser = ArgParser();
  parser.addFlag('testing');

  final ArgResults results = parser.parse(args);

  final String credentials =
      File('secret/gcp_credentials.json').readAsStringSync();
  final center = await FlutterCenter.makeDefault(
    jsonDecode(credentials),
    isTesting: results[kTestingFlag],
  );

  while (true) {
    print('Start synchronizing at ${DateTime.now()}');
    await center.synchronize();
    print('Finish synchronizing at ${DateTime.now()}');
    print('Sleep for $kSleepDuration...\n\n');
    await Future.delayed(kSleepDuration);
  }
}
