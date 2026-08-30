import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/migration.dart';

class MigrationFileException implements Exception {
  const MigrationFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlatformFileService {
  static const channel = MethodChannel('workfollow/platform');

  Future<String?> pickMigrationFile() async {
    return channel.invokeMethod<String>('pickMigrationFile');
  }

  Future<String?> applicationSupportDirectory() async {
    return channel.invokeMethod<String>('applicationSupportDirectory');
  }
}

class LocalWorkspaceStore {
  LocalWorkspaceStore({PlatformFileService? platform})
      : _platform = platform ?? PlatformFileService();

  static const snapshotFileName = 'workspace.json';

  final PlatformFileService _platform;
  Future<void> _pendingSave = Future<void>.value();

  Future<MigrationBundle?> load() async {
    final file = await _snapshotFile();
    if (file == null || !await file.exists()) return null;
    try {
      return MigrationBundle.fromJsonString(await file.readAsString());
    } on Object {
      // A damaged local snapshot should not prevent the app from opening with
      // its safe starter state. The next successful import replaces it.
      return null;
    }
  }

  Future<void> save(MigrationBundle bundle) async {
    // Task interactions can emit several saves in one event loop. Serialize
    // the writes so a newer snapshot never races an older temporary file.
    _pendingSave = _pendingSave.then((_) => _writeSnapshot(bundle));
    await _pendingSave;
  }

  Future<void> _writeSnapshot(MigrationBundle bundle) async {
    final file = await _snapshotFile();
    if (file == null) return;
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(bundle.toJson(outputFormat: localSnapshotFormat)),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<MigrationBundle?> pickAndReadMigration() async {
    final path = await _platform.pickMigrationFile();
    if (path == null || path.trim().isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw const MigrationFileException('找不到所选文件。');
      }
      return MigrationBundle.fromJsonString(await file.readAsString());
    } on MigrationFormatException {
      rethrow;
    } on MigrationFileException {
      rethrow;
    } on Object {
      throw const MigrationFileException('无法读取这个文件，请重新导出后再试。');
    }
  }

  Future<File?> _snapshotFile() async {
    try {
      final path = await _platform.applicationSupportDirectory();
      if (path == null || path.trim().isEmpty) return null;
      return File('$path/$snapshotFileName');
    } on MissingPluginException {
      // Unit/widget tests run without the macOS host channel.
      return null;
    } on PlatformException {
      return null;
    } on Object {
      // Keep the model layer usable in pure Dart tests and on unsupported
      // desktop hosts where no platform channel has been registered.
      return null;
    }
  }
}
