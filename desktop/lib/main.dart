import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
      const WorkFollowApp(demoMode: bool.fromEnvironment('WORKFOLLOW_DEMO')));
}
