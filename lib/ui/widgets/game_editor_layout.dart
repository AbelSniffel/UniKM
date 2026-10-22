import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_tab_bar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/settings/settings_model.dart' show SectionTitleLocation;
import '../../models/game.dart';
import '../../providers/settings_providers.dart';
import 'navigation_panel.dart' show isVeryNarrowAppLayout;
import 'cover_image_card.dart';
import 'dialog_helpers.dart';
import 'section_groupbox.dart';
import 'tag_list.dart';

/// Minimum content width for three cover-sized panels and their spacing.
const kGameEditorNotesBreakpoint =
    CoverImageCard.preferredWidth * 3 + kDialogSpacing * 2;

/// Responsive cover/information/notes placement shared by both game editors.
class GameEditorLayout extends ConsumerStatefulWidget {
  const GameEditorLayout({
    super.key,
    required this.theme,
    required this.titleController,
    required this.cover,
    required this.informationBuilder,
    required this.detailsBuilder,
    required this.tags,
    required this.notesController,
    required this.onNotesChanged,
    this.optionsBuilder,
    this.wideDetails,
    this.trailing,
  });

  final AppThemeData theme;
  final TextEditingController titleController;
  final Widget cover;
  final Widget Function(SectionGroupPosition position) informationBuilder;
  final Widget Function(Widget? information) detailsBuilder;

  /// When supplied, stack Options under Information beside the cover.
  final Widget Function(SectionGroupPosition position)? optionsBuilder;

  /// Optional remaining Details content after both groups move to the header.
  final Widget? wideDetails;
  final Widget tags;
  final TextEditingController notesController;
  final VoidCallback onNotesChanged;
  final Widget? trailing;

  @override
  ConsumerState<GameEditorLayout> createState() => GameEditorLayoutState();
}

class GameEditorLayoutState extends ConsumerState<GameEditorLayout>
    with TickerProviderStateMixin {
  late TabController _controller = TabController(
    length: 3,
    vsync: this,
    animationDuration: kTabTransition,
  );
  List<String> _tabs = ['Details', 'Tags', 'Notes'];
  final _notesKey = GlobalKey();

  void showDetails() {
    final index = _tabs.indexOf('Details');
    if (index >= 0) _controller.animateTo(index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigation = ref.watch(
      appShellSettingsProvider.select(
        (settings) => (settings.navBarPosition, settings.navBarAppearance),
      ),
    );
    final informationBesideCover = !isVeryNarrowAppLayout(
      MediaQuery.sizeOf(context).width,
      position: navigation.$1,
      appearance: navigation.$2,
    );
    final information = widget.informationBuilder(
      informationBesideCover
          ? SectionGroupPosition.only
          : SectionGroupPosition.first,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final notesBesideInformation =
            informationBesideCover &&
            constraints.maxWidth >= kGameEditorNotesBreakpoint;
        final optionsBesideCover =
            informationBesideCover && widget.optionsBuilder != null;
        final scaler = MediaQuery.textScalerOf(context);
        final headerBudget =
            constraints.maxHeight - scaler.scale(72) - 20 - 160;
        final details = optionsBesideCover
            ? widget.wideDetails
            : widget.detailsBuilder(
                informationBesideCover ? null : information,
              );
        final tabs = [
          if (details != null) 'Details',
          'Tags',
          if (!notesBesideInformation) 'Notes',
        ];
        if (!listEquals(_tabs, tabs)) {
          final selected = _tabs[_controller.index];
          final index = tabs.indexOf(selected);
          _controller.dispose();
          _controller = TabController(
            animationDuration: kTabTransition,
            length: tabs.length,
            initialIndex: index < 0 ? 0 : index,
            vsync: this,
          );
          _tabs = tabs;
        }
        final notes = GameEditorNotes(
          key: _notesKey,
          theme: widget.theme,
          controller: widget.notesController,
          onChanged: widget.onNotesChanged,
          padding: notesBesideInformation
              ? EdgeInsets.zero
              : const EdgeInsets.only(top: 16),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GameEditorHeader(
              theme: widget.theme,
              titleController: widget.titleController,
              cover: widget.cover,
              trailing: widget.trailing,
              information: informationBesideCover ? information : null,
              options: optionsBesideCover
                  ? widget.optionsBuilder!(SectionGroupPosition.only)
                  : null,
              maxPanelHeight: optionsBesideCover
                  ? math.max(scaler.scale(44) + 136, headerBudget)
                  : null,
              notes: notesBesideInformation ? notes : null,
            ),
            const SizedBox(height: kDialogSpacing),
            Expanded(
              child: GameEditorTabs(
                theme: widget.theme,
                controller: _controller,
                details: details,
                tags: widget.tags,
                notes: notesBesideInformation ? null : notes,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Shared title and cover placement for adding and editing a game.
class GameEditorHeader extends StatelessWidget {
  const GameEditorHeader({
    super.key,
    required this.theme,
    required this.titleController,
    required this.cover,
    this.information,
    this.options,
    this.maxPanelHeight,
    this.notes,
    this.trailing,
  });

  final AppThemeData theme;
  final TextEditingController titleController;
  final Widget cover;
  final Widget? information;
  final Widget? options;
  final double? maxPanelHeight;
  final Widget? notes;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final panelHeight = CoverImageCard.preferredWidth / 2 + scaler.scale(40);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: titleController,
                  builder: (context, value, _) => Text(
                    value.text.trim().isEmpty ? 'New Game' : value.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (information != null && options != null)
          LayoutBuilder(
            builder: (context, constraints) {
              final columnWidth =
                  (constraints.maxWidth -
                      CoverImageCard.preferredWidth -
                      kDialogSpacing * (notes == null ? 1 : 2)) /
                  (notes == null ? 1 : 2);
              // Only the field stack determines this Stack's natural height.
              // The cover and Notes fill it without imposing a height of their own.
              return Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      left: CoverImageCard.preferredWidth + kDialogSpacing,
                      right: notes == null ? 0 : columnWidth + kDialogSpacing,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: maxPanelHeight ?? double.infinity,
                      ),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            information!,
                            const SizedBox(height: kDialogSpacing),
                            options!,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: CoverImageCard.preferredWidth,
                    child: cover,
                  ),
                  if (notes != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: columnWidth,
                      child: notes!,
                    ),
                ],
              );
            },
          )
        else
          SizedBox(
            height: panelHeight,
            child: information == null && notes == null
                ? ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: CoverImageCard.preferredWidth,
                    ),
                    child: cover,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: CoverImageCard.preferredWidth,
                        child: cover,
                      ),
                      if (information != null) ...[
                        const SizedBox(width: kDialogSpacing),
                        Expanded(child: information!),
                      ],
                      if (notes != null) ...[
                        const SizedBox(width: kDialogSpacing),
                        Expanded(child: notes!),
                      ],
                    ],
                  ),
          ),
      ],
    );
  }
}

class GameEditorTabs extends StatelessWidget {
  const GameEditorTabs({
    super.key,
    required this.theme,
    required this.controller,
    required this.details,
    required this.tags,
    required this.notes,
  });

  final AppThemeData theme;
  final TabController controller;
  final Widget? details;
  final Widget tags;
  final Widget? notes;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppTabBar(
        theme: theme,
        controller: controller,
        tabs: [
          if (details != null) const AppTab('Details'),
          const AppTab('Tags'),
          if (notes != null) const AppTab('Notes'),
        ],
      ),
      Expanded(
        child: AppTabView(
          controller: controller,
          children: [?details, tags, ?notes],
        ),
      ),
    ],
  );
}

class GameEditorInformation extends StatelessWidget {
  const GameEditorInformation({
    super.key,
    required this.theme,
    required this.titleController,
    required this.keyController,
    this.platformSelector,
    this.isKeyVisible = true,
    this.onKeyVisibilityChanged,
    this.onCopyKey,
    required this.onTitleChanged,
    required this.onKeyChanged,
    this.enabled = true,
    this.titleLabel = 'Title',
    this.keyLabel = 'Game Key',
    this.titleValidator,
    this.keyValidator,
    this.groupPosition = SectionGroupPosition.first,
  });

  final AppThemeData theme;
  final TextEditingController titleController;
  final TextEditingController keyController;
  final Widget? platformSelector;
  final bool isKeyVisible;
  final bool enabled;
  final ValueChanged<bool>? onKeyVisibilityChanged;
  final VoidCallback? onCopyKey;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onKeyChanged;
  final String titleLabel;
  final String keyLabel;
  final FormFieldValidator<String>? titleValidator;
  final FormFieldValidator<String>? keyValidator;
  final SectionGroupPosition groupPosition;

  @override
  Widget build(BuildContext context) => SectionGroupBox(
    title: 'Information',
    theme: theme,
    titleIcon: Icons.info,
    titleLocation: SectionTitleLocation.top,
    headerCrossAxisAlignment: CrossAxisAlignment.center,
    trailing: platformSelector,
    groupPosition: groupPosition,
    child: SingleChildScrollView(
      child: Column(
        children: [
          TextFormField(
            controller: titleController,
            enabled: enabled,
            style: TextStyle(color: theme.textPrimary),
            decoration: InputDecoration(labelText: titleLabel),
            validator: titleValidator,
            onChanged: onTitleChanged,
            onFieldSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed != value) titleController.text = trimmed;
              onTitleChanged(trimmed);
            },
          ),
          const SizedBox(height: kDialogSpacing),
          TextFormField(
            controller: keyController,
            enabled: enabled,
            obscureText: !isKeyVisible,
            style: TextStyle(
              color: theme.textPrimary,
              fontFamily: 'monospace',
              letterSpacing: 1.5,
            ),
            decoration: InputDecoration(
              labelText: keyLabel,
              suffixIcon: onKeyVisibilityChanged == null && onCopyKey == null
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onKeyVisibilityChanged != null)
                          IconButton(
                            icon: Icon(
                              isKeyVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: theme.textSecondary,
                            ),
                            tooltip: isKeyVisible ? 'Hide key' : 'Show key',
                            onPressed: () =>
                                onKeyVisibilityChanged!(!isKeyVisible),
                          ),
                        if (onCopyKey != null)
                          IconButton(
                            icon: Icon(Icons.copy, color: theme.accent),
                            tooltip: 'Copy key',
                            onPressed: onCopyKey,
                          ),
                      ],
                    ),
            ),
            validator: keyValidator,
            onChanged: onKeyChanged,
          ),
        ],
      ),
    ),
  );
}

class GameEditorTags extends StatelessWidget {
  const GameEditorTags({
    super.key,
    required this.theme,
    required this.customTags,
    required this.selectedTagIds,
    required this.onTagToggled,
    required this.steamTags,
  });

  final AppThemeData theme;
  final List<Tag> customTags;
  final Set<int> selectedTagIds;
  final ValueChanged<int> onTagToggled;
  final List<Tag> steamTags;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(top: 16),
    children: [
      SectionGroupBox(
        title: 'Custom Tags',
        description: 'click to add/remove',
        theme: theme,
        titleIcon: Icons.label,
        groupPosition: SectionGroupPosition.first,
        child: customTags.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No custom tags created yet',
                  style: TextStyle(color: theme.textHint),
                  textAlign: TextAlign.center,
                ),
              )
            : SizedBox(
                height: 120,
                child: TagList(
                  tags: customTags,
                  theme: theme,
                  selectedTagIds: selectedTagIds,
                  onTagToggled: onTagToggled,
                  showSearch: true,
                ),
              ),
      ),
      SectionGroupBox(
        title: 'Steam Tags',
        description: 'auto-managed',
        theme: theme,
        titleIcon: FontAwesomeIcons.steam.data,
        groupPosition: SectionGroupPosition.last,
        alternateBackground: true,
        child: steamTags.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No Steam tags imported yet',
                  style: TextStyle(color: theme.textHint),
                  textAlign: TextAlign.center,
                ),
              )
            : TagList(tags: steamTags, theme: theme, allSelected: true),
      ),
    ],
  );
}

class GameEditorNotes extends StatelessWidget {
  const GameEditorNotes({
    super.key,
    required this.theme,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
    this.padding = const EdgeInsets.only(top: 16),
  });

  final AppThemeData theme;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool enabled;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: SectionGroupBox(
      title: 'Notes',
      theme: theme,
      titleIcon: Icons.notes,
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(color: theme.textPrimary),
        decoration: InputDecoration(
          constraints: const BoxConstraints(minHeight: 0),
          filled: true,
          fillColor: theme.inputBackground,
          hintText: 'Add notes about this game...',
          hintStyle: TextStyle(color: theme.textHint),
          border: theme.resolveInputBorder(showTopBorder: true),
        ),
        onChanged: (_) => onChanged(),
      ),
    ),
  );
}
