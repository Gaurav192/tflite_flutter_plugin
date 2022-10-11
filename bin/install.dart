import 'dart:convert';
import 'dart:core';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/args.dart';

var tfVersion = '2.5';
const url = "https://github.com/am15h/tflite_flutter_plugin/releases/download/";
var tag = "tf_$tfVersion";
const availableVersions = ['2.5', '2.4.1'];

void main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('d', defaultsTo: false)
    ..addOption(
      'version',
      help: 'set version from ',
      allowed: availableVersions,
      defaultsTo: '2.5',
    );
  ArgResults argResults = parser.parse(args);
  final useDelegate = argResults['d'] as bool;
  tfVersion = argResults['version'] as String;
  var location = Platform.script.toString();
  var isNewFlutter = location.contains(".snapshot");
  if (isNewFlutter) {
    var sp = Platform.script.toFilePath();
    var sd = sp.split(Platform.pathSeparator);
    sd.removeLast();
    var scriptDir = sd.join(Platform.pathSeparator);
    var packageConfigPath = [scriptDir, '..', '..', '..', 'package_config.json']
        .join(Platform.pathSeparator);
    var jsonString = File(packageConfigPath).readAsStringSync();
    Map<String, dynamic> packages = jsonDecode(jsonString);
    var packageList = packages["packages"];
    String? tfliteFileUri;
    for (var package in packageList) {
      if (package["name"] == "tflite_flutter") {
        tfliteFileUri = package["rootUri"];
        break;
      }
    }
    if (tfliteFileUri == null) {
      print("tflite_flutter package not found!");
      return;
    }
    location = tfliteFileUri;
  }
  if (Platform.isWindows) {
    location = location.replaceFirst("file:///", "");
  } else {
    location = location.replaceFirst("file://", "");
  }
  if (!isNewFlutter) {
    location = location.replaceFirst("/bin/setup_sdk.dart", "");
  }
  await downloadAndroidLibs(location, useDelegate: useDelegate);
  if (Platform.isMacOS) await downloadIOSLibs(location);
}

Future<void> downloadIOSLibs(String location) async {
  var directory = location + '/ios/TensorFlowLiteC.framework';
  bool exists = await Directory(directory).exists();
  final zipFileLocation = '$location/ios/TensorFlowLiteC.framework.zip';

  if (exists) return;
  await downloadFile(
      Uri.parse(
          'https://github.com/am15h/tflite_flutter_plugin/releases/download/v0.5.0/TensorFlowLiteC.framework.zip'),
      zipFileLocation);
  final zipExists = File(zipFileLocation).existsSync();
  if (!zipExists) return;
  final inputStream = InputFileStream(zipFileLocation);
  final archive = ZipDecoder().decodeBuffer(inputStream);
  for (var file in archive.files) {
    if (file.isFile) {
      final outputStream = OutputFileStream('$location/ios/${file.name}');
      file.writeContent(outputStream);
      outputStream.close();
    }
  }
  await inputStream.close();
  File(zipFileLocation).deleteSync();
}

Future<void> downloadAndroidLibs(String location,
    {bool useDelegate = false}) async {
  final directory = "$location/android/app/src/main/jniLibs/";
  const androidLib = "libtensorflowlite_c.so";
  final filesList = {
    'armeabi-v7a': useDelegate
        ? "libtensorflowlite_c_arm_delegate.so"
        : "libtensorflowlite_c_arm.so",
    'arm64-v8a': useDelegate
        ? "libtensorflowlite_c_arm64_delegate.so"
        : 'libtensorflowlite_c_arm64.so',
    'x86': 'libtensorflowlite_c_x86_delegate.so',
    'x86_64': "libtensorflowlite_c_x86_64_delegate.so",
  };

  await Future.wait(filesList.entries.map((e) async {
    final fileLocation = '$directory${e.key}/$androidLib';
    final exists = await File(fileLocation).exists();
    if (!exists)
      return downloadFile(Uri.parse('$url$tag/${e.value}'), fileLocation);
  }));
}

Future<void> downloadFile(Uri uri, String savePath) async {
  print('Download ${uri.toString()} to $savePath');
  File destinationFile = await File(savePath).create(recursive: true);
  final request = await HttpClient().getUrl(uri);
  final response = await request.close();
  await response.pipe(destinationFile.openWrite());
}
