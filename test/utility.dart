import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Map<String, dynamic> getGcpCredentialsJson() {
  return jsonDecode(File('secret/gcp_credentials.json').readAsStringSync());
}

void expectSetMatch<T>(Iterable<T> actual, Iterable<T> expected) {
  expect(Set<T>.from(actual), equals(Set<T>.from(expected)));
}
