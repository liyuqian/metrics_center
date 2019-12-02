import 'dart:convert';
import 'dart:io';

Map<String, dynamic> getGcpCredentialsJson() {
  final gcpCredentialsDir = Directory('secret/gcp_credentials');
  assert(gcpCredentialsDir.existsSync());
  final List<FileSystemEntity> credentialFiles = gcpCredentialsDir.listSync();
  assert(credentialFiles.length == 1);
  final credentialFile = File(credentialFiles[0].uri.toFilePath());
  return jsonDecode(credentialFile.readAsStringSync());
}
