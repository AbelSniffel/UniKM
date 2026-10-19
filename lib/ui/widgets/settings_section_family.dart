import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import 'section_groupbox.dart';

/// A settings family with its title above the spaced groupboxes.
class SettingsSectionFamily extends StatelessWidget {
  const SettingsSectionFamily({
    super.key,
    required this.header,
    required this.child,
  });

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      header,
      const SizedBox(height: kGroupBoxSpacing),
      SpacedSettingsGroups(child: child),
    ],
  );
}
