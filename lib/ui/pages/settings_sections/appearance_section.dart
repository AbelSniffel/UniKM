/// Appearance settings: themes and the background pattern.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../widgets/animated_popover.dart';
import '../../widgets/app_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:unikm/core/constants/app_constants.dart';

import '../../../core/services/platform_file_actions.dart';
import '../../../core/settings/settings_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/custom_theme_actions.dart';
import '../../widgets/preview_card.dart';
import '../../widgets/navigation_panel_overlay.dart';
import '../../widgets/notification_system.dart';
import '../../widgets/section_groupbox.dart';
import '../../widgets/settings_header_actions.dart';
import '../../widgets/theme_preview_card.dart';
import '../../widgets/theme_picker_actions.dart';
import '../../widgets/app_tab_bar.dart';
import 'settings_common.dart';
import 'settings_control_cards.dart';
import 'settings_theme_editor.dart';

/// Appearance settings section
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({
    super.key,
    required this.theme,
    this.searchQuery = '',
    required this.matchesSearch,
    this.attachesToAbove = false,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool Function(String) matchesSearch;
  final bool attachesToAbove;

  static const SettingTextSpec backgroundPatternSpec = SettingTextSpec(
    label: 'Background pattern',
    description: 'Decorates the navigation panel, other panels and pages',
  );
  static const SettingTextSpec patternStrengthSpec = SettingTextSpec(
    label: 'Pattern strength',
  );
  static const SettingTextSpec patternAngleSpec = SettingTextSpec(
    label: 'Pattern angle',
  );
  static const SettingTextSpec lineShapeSpec = SettingTextSpec(
    label: 'Line shape',
  );
  static const SettingTextSpec pagePatternSpec = SettingTextSpec(
    label: 'Show on pages',
    description:
        'A much fainter copy of the pattern behind every page, seen through tinted group boxes',
    icon: Icons.wallpaper,
  );
  static const SettingsSearchGroup themeSearchGroup = SettingsSearchGroup(
    title: 'Theme',
    settings: [],
    extraTexts: [
      'Built-in themes',
      'Default themes',
      'Custom themes',
      'All themes',
      'Create Theme',
      'Edit Theme',
      'Edit current theme',
      'Modify current custom theme',
      'Import Theme',
      'Export Theme',
      'Remove Theme',
      'Delete Theme',
      'Delete current theme',
    ],
  );

  static SettingsSearchGroup get backgroundPatternSearchGroup =>
      SettingsSearchGroup(
        title: 'Background Pattern',
        settings: [
          backgroundPatternSpec,
          patternStrengthSpec,
          pagePatternSpec,
          patternAngleSpec,
          lineShapeSpec,
        ],
        extraTexts: [
          for (final style in NavPanelOverlayStyle.values) style.displayName,
          'Overlay',
          'Navigation panel background',
          'Panel pattern',
          'Settings section list',
          'Selection ribbon',
          'Direction',
          'Rotation',
          'Waves',
          'Zigzag',
        ],
      );

  static List<SettingsSearchGroup> get searchGroups => [
    themeSearchGroup,
    backgroundPatternSearchGroup,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(customThemesJsonProvider);
    final current = ref.watch(themeProvider);
    final builtInOverlayStyle = ref.watch(navPanelOverlayStyleSettingProvider);
    final builtInThemes = AppThemeData.builtInThemes;
    final themeNotifier = ref.read(themeProvider.notifier);
    final allThemes = themeNotifier.getAllThemes();
    final builtInIds = builtInThemes.map((theme) => theme.id).toSet();
    final customThemes = allThemes
        .where((t) => !builtInIds.contains(t.id))
        .toList();
    final isSearching = searchQuery.trim().isNotEmpty;
    final selectedTab = ref.watch(appearanceThemeTabProvider);
    List<AppThemeData> themesForTab(int tab) =>
        tab == 0 ? builtInThemes : customThemes;
    // A name search can reveal a theme in the other collection without
    // replacing the user's remembered tab.
    final otherTab = 1 - selectedTab;
    final visibleTab =
        isSearching &&
            !themesForTab(selectedTab).any((t) => matchesSearch(t.name)) &&
            themesForTab(otherTab).any((t) => matchesSearch(t.name))
        ? otherTab
        : selectedTab;
    final visibleThemes = themesForTab(visibleTab);
    // Edit and Delete act on the active custom theme, on the Custom tab only.
    final canManageCurrent =
        visibleTab == 1 && !builtInIds.contains(current.id);

    // Check which sections match search
    bool themeNameMatches() =>
        builtInThemes.any((t) => matchesSearch(t.name)) ||
        customThemes.any((t) => matchesSearch(t.name));
    final showThemeSection =
        shouldShowSettingsGroup(
          query: searchQuery,
          matchesSearch: matchesSearch,
          group: themeSearchGroup,
        ) ||
        themeNameMatches();
    final showPatternSection = shouldShowSettingsGroup(
      query: searchQuery,
      matchesSearch: matchesSearch,
      group: backgroundPatternSearchGroup,
    );
    if (isSearching && !showThemeSection && !showPatternSection) {
      return const SizedBox.shrink();
    }

    return SettingsSectionGroups(
      attachesToAbove: attachesToAbove,
      entries: [
        buildSearchableSectionEntry(
          visible: showThemeSection,
          theme: theme,
          group: themeSearchGroup,
          titleIcon: Icons.color_lens,
          searchQuery: searchQuery,
          matchesSearch: matchesSearch,
          extraMatch: themeNameMatches,
          childBuilder: () => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTabBar(
                theme: theme,
                tabs: const [AppTab('Default'), AppTab('Custom')],
                selectedIndex: visibleTab,
                onChanged: (index) => ref
                    .read(appearanceThemeTabProvider.notifier)
                    .setIndex(index),
              ),
              const SizedBox(height: 10),
              // Only the panel animates its height, so the actions below
              // move with the groupbox instead of jumping to their place.
              _animatedPanelHeight(
                context,
                AppTabTransition(
                  index: visibleTab,
                  child: visibleThemes.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'No custom themes yet.\nCreate one from your current colors.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.textSecondary),
                            ),
                          ),
                        )
                      : PreviewCardWrap(
                          spacing: kElementHSpacing,
                          runSpacing: 10,
                          children: [
                            for (final themeData in visibleThemes)
                              ThemePreviewCard(
                                key: ValueKey(themeData.id),
                                data: themeData,
                                theme: theme,
                                preview: builtInIds.contains(themeData.id)
                                    ? themeData.copyWith(
                                        navPanelOverlayStyle:
                                            builtInOverlayStyle,
                                      )
                                    : themeData,
                                selected: current.id == themeData.id,
                                onDoubleTap: builtInIds.contains(themeData.id)
                                    ? null
                                    : () => _openThemeEditor(
                                        context,
                                        ref,
                                        existing: themeData,
                                      ),
                                onTap: () => ref
                                    .read(themeProvider.notifier)
                                    .setTheme(themeData),
                              ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 10),
              ThemePickerActions(
                theme: theme,
                onCreate: () => _openThemeEditor(context, ref),
                onEdit: canManageCurrent
                    ? () => _openThemeEditor(context, ref, existing: current)
                    : null,
                onDelete: canManageCurrent
                    ? () => deleteCustomThemeWithConfirmation(
                        context,
                        ref,
                        current.id,
                        current.name,
                      )
                    : null,
              ),
            ],
          ),
        ),
        SectionGroupEntry(
          visible: showPatternSection,
          builder: (position, isAlternate) => _BackgroundPatternSection(
            theme: theme,
            searchQuery: searchQuery,
            isSearchMatch: isSearching,
            groupPosition: position,
            isAlternate: isAlternate,
          ),
        ),
      ],
    );
  }
}

Widget _animatedPanelHeight(BuildContext context, Widget panel) =>
    MediaQuery.disableAnimationsOf(context)
    ? panel
    : AnimatedSize(
        key: const ValueKey('appearance-theme-size'),
        duration: kTabTransition,
        curve: kTabTransitionCurve,
        alignment: Alignment.topLeft,
        child: panel,
      );

void _openThemeEditor(
  BuildContext context,
  WidgetRef ref, {
  AppThemeData? existing,
}) {
  // Capture before opening: resizing may replace the footer while the editor
  // stays open, so its route builder must not read the initiating widget ref.
  final theme = ref.read(effectiveThemeProvider);
  showAppDialog<void>(
    context: context,
    builder: (_) => ThemeEditorDialog(theme: theme, existingTheme: existing),
  );
}

Future<void> _importThemes(BuildContext context, WidgetRef ref) async {
  try {
    final result = await FilePicker.pickFile(
      dialogTitle: 'Import Theme',
      type: FileType.any,
    );

    final selectedPath = result?.path;
    if (selectedPath == null || selectedPath.isEmpty) return;
    if (!selectedPath.toLowerCase().endsWith('.json')) {
      NotificationManager.instance.error(
        'Unsupported file type. Please select a .json theme file.',
      );
      return;
    }

    final content = await File(selectedPath).readAsString();
    final importResult = await ref
        .read(themeProvider.notifier)
        .importThemesFromJsonString(content);

    if (importResult.importedCount == 0) {
      NotificationManager.instance.warning('No themes were imported from file');
      return;
    }

    final invalid = importResult.invalidCount;
    NotificationManager.instance.success(
      'Imported ${importResult.importedCount} theme(s)'
      '${invalid > 0 ? ' • $invalid invalid' : ''}',
    );
  } on FormatException catch (e) {
    NotificationManager.instance.error('Import failed: ${e.message}');
  } catch (e) {
    NotificationManager.instance.error('Import failed: $e');
  }
}

Future<void> _exportTheme(
  BuildContext context,
  WidgetRef ref,
  AppThemeData selectedTheme,
) async {
  try {
    final defaultName =
        '${selectedTheme.name.toLowerCase().replaceAll(' ', '_')}_theme.json';
    final target = await PlatformFileActions.prepareExportTarget(
      dialogTitle: 'Export Theme',
      fileName: defaultName,
      allowedExtensions: const ['json'],
    );

    if (target == null) return;

    final content = ref
        .read(themeProvider.notifier)
        .exportThemesToJson(themes: [selectedTheme]);
    await target.file.writeAsString(content);

    if (!await PlatformFileActions.completeExport(
      target,
      subject: 'UniKM theme export',
    )) {
      return;
    }

    NotificationManager.instance.success(
      'Theme "${selectedTheme.name}" exported to ${p.basename(target.file.path)}',
    );
  } catch (e) {
    NotificationManager.instance.error('Export failed: $e');
  }
}

/// Import/export actions shared by the Appearance and search-result headers.
class ThemeHeaderActions extends ConsumerWidget {
  const ThemeHeaderActions({super.key, this.expanded = false});

  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final buttons = <Widget>[
      SettingsHeaderAction(
        theme: theme,
        icon: Icons.download,
        tooltip: 'Import Theme',
        onTap: () => _importThemes(context, ref),
      ),
      SettingsHeaderAction(
        theme: theme,
        icon: Icons.upload,
        tooltip: 'Export Theme',
        onTap: theme.id.isEmpty
            ? null
            : () => _exportTheme(context, ref, theme),
      ),
    ];
    return SettingsHeaderActions(
      theme: theme,
      expanded: expanded,
      children: buttons,
    );
  }
}

// ---------------------------------------------------------------------------
// Background pattern selector
// ---------------------------------------------------------------------------

class _BackgroundPatternSection extends ConsumerStatefulWidget {
  const _BackgroundPatternSection({
    required this.theme,
    required this.searchQuery,
    required this.isSearchMatch,
    this.groupPosition = SectionGroupPosition.only,
    this.isAlternate = false,
  });

  final AppThemeData theme;
  final String searchQuery;
  final bool isSearchMatch;
  final SectionGroupPosition groupPosition;
  final bool isAlternate;

  @override
  ConsumerState<_BackgroundPatternSection> createState() =>
      _BackgroundPatternSectionState();
}

class _BackgroundPatternSectionState
    extends ConsumerState<_BackgroundPatternSection> {
  /// The styles an open popover changes; the other cards dim until it closes.
  Set<NavPanelOverlayStyle> _highlighted = const {};

  ValueChanged<bool> _highlightWhileOpen(
    Iterable<NavPanelOverlayStyle> styles,
  ) =>
      (open) => setState(() => _highlighted = open ? styles.toSet() : const {});

  /// The Line shape steps' names, from straight to zigzag.
  static const _lineShapes = ['Straight', 'Gentle', 'Wavy', 'Sharp', 'Zigzag'];

  /// Built-in themes keep the pattern as a setting; custom themes save it.
  Future<void> _apply(NavPanelOverlayStyle style) async {
    if (ref.read(effectiveNavPanelOverlayStyleProvider) == style) return;
    if (ref.read(currentThemeIsBuiltInProvider)) {
      await ref
          .read(settingsProvider.notifier)
          .setSetting(SettingsKeys.navPanelOverlayStyle, style);
      return;
    }
    await ref
        .read(themeProvider.notifier)
        .saveCustomTheme(
          ref.read(themeProvider).copyWith(navPanelOverlayStyle: style),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final currentTheme = ref.watch(themeProvider);
    final effectiveTheme = ref.watch(effectiveThemeProvider);
    final strength = ref.watch(patternStrengthProvider);
    final angle = ref.watch(patternAngleProvider);
    final wave = ref.watch(patternWaveProvider);
    final shape = _lineShapes[(wave * 4).round()];
    final settingsNotifier = ref.read(settingsProvider.notifier);
    const pagesSpec = AppearanceSection.pagePatternSpec;
    final percent = '${(strength * 100).round()}%';

    return SectionGroupBox(
      title: AppearanceSection.backgroundPatternSearchGroup.title,
      theme: theme,
      titleIcon: Icons.layers_outlined,
      headerCrossAxisAlignment: CrossAxisAlignment.center,
      searchQuery: widget.searchQuery,
      isSearchMatch: widget.isSearchMatch,
      groupPosition: widget.groupPosition,
      alternateBackground: widget.isAlternate,
      // The icon buttons' own padding spaces them, so narrow headers fit.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderPopoverButton(
            theme: theme,
            title: AppearanceSection.patternStrengthSpec.label,
            value: percent,
            icon: CustomPaint(
              size: const Size.square(26),
              painter: _StrengthDropPainter(strength, theme.accent),
            ),
            // In quarter steps.
            slider: Slider(
              value: strength,
              min: kMinPatternStrength,
              max: kMaxPatternStrength,
              divisions: 4,
              label: percent,
              onChanged: (value) => settingsNotifier.setSetting(
                SettingsKeys.patternStrength,
                (value * 4).round() / 4,
              ),
            ),
          ),
          SliderPopoverButton(
            theme: theme,
            title: AppearanceSection.patternAngleSpec.label,
            value: '$angle°',
            // Points the way the gradient runs, across the stripes.
            icon: Transform.rotate(
              angle: angle * math.pi / 180,
              child: Icon(
                Icons.arrow_forward_rounded,
                color: theme.accent,
                size: 26,
              ),
            ),
            onOpenChanged: _highlightWhileOpen(
              NavPanelOverlayStyle.values.where((style) => style.usesAngle),
            ),
            action: TextButton(
              onPressed: angle == DefaultSettings.patternAngle
                  ? null
                  : () => settingsNotifier.setSetting(
                      SettingsKeys.patternAngle,
                      DefaultSettings.patternAngle,
                    ),
              child: const Text('Default'),
            ),
            // In 15° steps.
            slider: Slider(
              value: angle.toDouble(),
              max: 180,
              divisions: 12,
              label: '$angle°',
              onChanged: (value) => settingsNotifier.setSetting(
                SettingsKeys.patternAngle,
                value.round(),
              ),
            ),
          ),
          SliderPopoverButton(
            theme: theme,
            title: AppearanceSection.lineShapeSpec.label,
            value: shape,
            icon: Icon(
              wave == 0
                  ? Icons.horizontal_rule_rounded
                  : wave < 0.75
                  ? Icons.waves_rounded
                  : Icons.show_chart_rounded,
              color: theme.accent,
              size: 26,
            ),
            onOpenChanged: _highlightWhileOpen(const [
              NavPanelOverlayStyle.diagonalStripes,
            ]),
            slider: Slider(
              value: wave,
              divisions: 4,
              label: shape,
              onChanged: (value) => settingsNotifier.setSetting(
                SettingsKeys.patternWave,
                (value * 4).round() / 4,
              ),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          PreviewCardWrap(
            children: [
              for (final style in NavPanelOverlayStyle.values)
                // While a popover highlights some styles, the rest fade back.
                AnimatedOpacity(
                  key: ValueKey(style),
                  opacity: _highlighted.isEmpty || _highlighted.contains(style)
                      ? 1
                      : 0.35,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: PreviewCard(
                    name: style.displayName,
                    theme: theme,
                    isSelected: effectiveTheme.navPanelOverlayStyle == style,
                    onTap: () => _apply(style),
                    backgroundBuilder: (context, _) => ColoredBox(
                      color: effectiveTheme.navBackground,
                      child: CustomPaint(
                        painter: BackgroundPatternPainter(
                          theme: currentTheme.copyWith(
                            navPanelOverlayStyle: style,
                          ),
                          angle: angle,
                          wave: wave,
                          strength: strength,
                          preview: true,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SettingsToggleCard(
            theme: theme,
            label: pagesSpec.label,
            description: pagesSpec.description,
            icon: pagesSpec.icon,
            value: ref.watch(pagePatternProvider),
            // Without a pattern there is nothing to show on pages.
            onChanged:
                effectiveTheme.navPanelOverlayStyle == NavPanelOverlayStyle.none
                ? null
                : settingsNotifier.setter(SettingsKeys.pagePattern),
          ),
        ],
      ),
    );
  }
}

/// The strength button's water drop: filled from the bottom up to 100%,
/// with a sparkle beside it beyond that.
class _StrengthDropPainter extends CustomPainter {
  const _StrengthDropPainter(this.strength, this.color);

  final double strength;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    // Material's water drop outline, from y 2 to 22 in its 24 px box.
    final drop = Path()
      ..moveTo(12, 2)
      ..cubicTo(6.67, 6.55, 4, 10.48, 4, 13.8)
      ..cubicTo(4, 18.78, 7.8, 22, 12, 22)
      ..cubicTo(16.2, 22, 20, 18.78, 20, 13.8)
      ..cubicTo(20, 10.48, 17.33, 6.55, 12, 2)
      ..close();
    final paint = Paint()..color = color;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(0, 22 - 20 * strength.clamp(0.0, 1.0), 24, 24),
    );
    canvas.drawPath(drop, paint);
    canvas.restore();
    canvas.drawPath(
      drop,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    if (strength > 1) {
      canvas.drawPath(
        Path()..addPolygon(const [
          Offset(20.5, 0),
          Offset(21.5, 2.5),
          Offset(24, 3.5),
          Offset(21.5, 4.5),
          Offset(20.5, 7),
          Offset(19.5, 4.5),
          Offset(17, 3.5),
          Offset(19.5, 2.5),
        ], true),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StrengthDropPainter oldDelegate) =>
      oldDelegate.strength != strength || oldDelegate.color != color;
}
