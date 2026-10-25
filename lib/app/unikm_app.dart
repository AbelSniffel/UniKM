import 'package:flutter/material.dart';

import '../ui/app_scaffold.dart';

/// Root application widget
///
/// Note: Theme is provided by the bootstrap MaterialApp.
/// This widget only provides the app scaffold content.
class UniKMApp extends StatelessWidget {
  const UniKMApp({super.key});

  @override
  Widget build(BuildContext context) => const AppScaffold();
}
