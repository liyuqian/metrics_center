import 'dart:convert';
import 'dart:io';

Map<String, dynamic> getGcpCredentialsJson() {
  return jsonDecode(File('secret/gcp_credentials.json').readAsStringSync());
}
