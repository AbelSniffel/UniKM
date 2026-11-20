import 'package:material_ui/material_ui.dart';

import '../ui/app_scaffold.dart';
import '../ui/widgets/double_back_to_exit.dart';

/// Root application widget
///
/// Note: Theme is provided by the bootstrap MaterialApp.
/// This widget only provides the app scaffold content.
class const UniKMApp({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const DoubleBackToExit(child: AppScaffold());
}
