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

/// Distinguishes "no snapshot yet" from "the snapshot exists but is damaged".
class WorkspaceSnapshotLoad {
  const WorkspaceSnapshotLoad({this.bundle, this.error});

  final MigrationBundle? bundle;

  /// The parse failure, when the snapshot file exists but cannot be read.
  final Object? error;

  bool get failed => error != null;
}

/// Snapshot backup overview for the settings page.
class WorkspaceBackupInfo {
  const WorkspaceBackupInfo({this.count = 0, this.latestAt, this.file});

  final int count;
  final DateTime? latestAt;
  final File? file;

  bool get exists => count > 0;
}

class LocalWorkspaceStore {
  LocalWorkspaceStore({PlatformFileService? platform})
      : _platform = platform ?? PlatformFileService();

  static const snapshotFileName = 'workspace.json';
  static const backupFolderName = 'backups';

  /// Keep one backup per day for the last week (see [_maintainDailyBackup]).
  static const backupRetentionDays = 7;

  final PlatformFileService _platform;
  Future<void> _pendingSave = Future<void>.value();

  /// Latest successful snapshot backup, plus how many exist.
  Future<WorkspaceBackupInfo> backupInfo() async {
    final backups = await _listBackups();
    if (backups.isEmpty) return const WorkspaceBackupInfo();
    final latest = backups.last;
    final date = DateTime.tryParse(_backupDateStamp(latest) ?? '');
    return WorkspaceBackupInfo(
        count: backups.length, latestAt: date, file: latest);
  }

  /// Forces a backup copy right now ("立即备份" entry point).
  Future<void> backupNow() async {
    final file = await _snapshotFile();
    if (file == null || !await file.exists()) return;
    await _copyToBackup(file, DateTime.now());
  }

  Future<WorkspaceSnapshotLoad> load() async {
    final file = await _snapshotFile();
    if (file == null || !await file.exists()) {
      return const WorkspaceSnapshotLoad();
    }
    try {
      return WorkspaceSnapshotLoad(
          bundle: MigrationBundle.fromJsonString(await file.readAsString()));
    } on Object catch (error) {
      // The original file stays untouched; the caller must pause auto-save
      // instead of overwriting possibly recoverable data with starter state.
      return WorkspaceSnapshotLoad(error: error);
    }
  }

  Future<void> save(MigrationBundle bundle) {
    // Task interactions can emit several saves in one event loop. Serialize
    // the writes so a newer snapshot never races an older temporary file.
    final result = _pendingSave.then((_) => _writeSnapshot(bundle));
    // A failed write must not poison the queue: the caller below still sees
    // the error, but later saves keep running.
    _pendingSave = result.then<void>((_) {}, onError: (Object _) {});
    return result;
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
    // The first successful write of each day leaves a restore point. Backup
    // problems must never break saving, so failures are swallowed here.
    await _maintainDailyBackup(file);
  }

  /// Copies the snapshot to `backups/workspace-<date>.json` once per day and
  /// prunes older copies beyond [backupRetentionDays].
  Future<void> _maintainDailyBackup(File snapshot) async {
    try {
      final now = DateTime.now();
      final backups = await _listBackups();
      final stamp = _stampFor(now);
      final todayAlreadyBackedUp =
          backups.any((file) => _backupDateStamp(file) == stamp);
      if (!todayAlreadyBackedUp) {
        await _copyToBackup(snapshot, now);
      }
      final all = await _listBackups();
      final removable = all.length > backupRetentionDays
          ? all.take(all.length - backupRetentionDays).toList()
          : const <File>[];
      for (final file in removable) {
        try {
          await file.delete();
        } on Object {
          // A stuck backup file is not worth failing a save over.
        }
      }
    } on Object {
      // Never let backup bookkeeping break the actual save.
    }
  }

  Future<void> _copyToBackup(File snapshot, DateTime now) async {
    final directory = Directory('${snapshot.parent.path}/$backupFolderName');
    await directory.create(recursive: true);
    final target = File('${directory.path}/workspace-${_stampFor(now)}.json');
    await snapshot.copy(target.path);
  }

  Future<List<File>> _listBackups() async {
    final file = await _snapshotFile();
    if (file == null) return const [];
    final directory = Directory('${file.parent.path}/$backupFolderName');
    if (!await directory.exists()) return const [];
    final files = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.path.endsWith('.json') &&
          _backupDateStamp(entity) != null) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  String _stampFor(DateTime time) => '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';

  String? _backupDateStamp(File file) {
    final name = file.uri.pathSegments.last;
    final match =
        RegExp(r'^workspace-(\d{4}-\d{2}-\d{2})\.json$').firstMatch(name);
    return match?.group(1);
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
