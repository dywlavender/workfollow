import 'dart:convert';
import 'dart:io';

import 'local_workspace_store.dart';

/// Tiny JSON-backed preferences (currently the appearance mode). Stored next
/// to the workspace snapshot so no extra plugin or entitlement is needed.
/// The file is a few dozen bytes and written rarely, so it uses synchronous
/// IO (like NSUserDefaults) — that also keeps it testable inside the widget
/// test binding's fake-async zone, where async file writes never land.
class WorkspacePreferencesStore {
  WorkspacePreferencesStore({
    PlatformFileService? platform,
    String? directoryOverride,
  })  : _platform = platform ?? PlatformFileService(),
        _directoryOverride = directoryOverride;

  static const fileName = 'preferences.json';

  final PlatformFileService _platform;
  final String? _directoryOverride;

  Future<Map<String, dynamic>> load() async {
    final file = await _preferencesFile();
    if (file == null || !file.existsSync()) return const {};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return const {};
    } on Object {
      // A damaged preferences file behaves like no preferences.
      return const {};
    }
  }

  Future<void> save(Map<String, dynamic> preferences) async {
    final file = await _preferencesFile();
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(preferences), flush: true);
    } on Object {
      // Preference persistence is best-effort; a failed write must not take
      // the app down.
    }
  }

  Future<File?> _preferencesFile() async {
    try {
      final path =
          _directoryOverride ?? await _platform.applicationSupportDirectory();
      if (path == null || path.trim().isEmpty) return null;
      return File('$path/$fileName');
    } on Object {
      // Pure Dart tests and unsupported hosts simply get no persistence.
      return null;
    }
  }
}
