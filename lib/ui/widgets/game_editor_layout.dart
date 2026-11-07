/// The layout both game editors share, styled like a store page.
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import 'cover_image_card.dart';
import 'dialog_helpers.dart';
import 'game_cover_image.dart';
import 'notification_system.dart';
import 'tag_list.dart';

/// How long ago [date] was, in whole days, months or years.
String daysAgoLabel(DateTime date) {
  final days = DateUtils.dateOnly(
    DateTime.now(),
  ).difference(DateUtils.dateOnly(date)).inDays;
  String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'} ago';
  return switch (days) {
    <= 0 => 'Today',
    1 => 'Yesterday',
    < 30 => plural(days, 'day'),
    < 365 => plural(days ~/ 30, 'month'),
    _ => plural(days ~/ 365, 'year'),
  };
}

/// A banner with the cover, title, key and status pills over the cover's
/// blurred art, then the notes beside the tags and a strip of [stats].
class GameEditorLayout extends StatelessWidget {
  const GameEditorLayout({
    super.key,
    required this.theme,
    required this.cover,
    required this.coverController,
    required this.actions,
    this.heading,
    required this.titleController,
    required this.onTitleChanged,
    this.titleValidator,
    required this.keyField,
    required this.platform,
    required this.options,
    required this.notesController,
    required this.onNotesChanged,
    required this.customTags,
    required this.selectedTagIds,
    required this.onTagToggled,
    required this.steamTags,
    this.stats = const [],
    this.cornerRadius = 0,
  });

  final AppThemeData theme;

  /// The cover card, and the path its art is drawn from behind the banner.
  final Widget cover;
  final TextEditingController coverController;

  /// Buttons for the top right of the banner.
  final List<Widget> actions;

  /// The dialog's name, at the left of [actions].
  final String? heading;
  final TextEditingController titleController;
  final ValueChanged<String> onTitleChanged;
  final FormFieldValidator<String>? titleValidator;
  final Widget keyField;
  final Widget platform;
  final Widget options;
  final TextEditingController notesController;
  final VoidCallback onNotesChanged;
  final List<Tag> customTags;
  final Set<int> selectedTagIds;
  final ValueChanged<int> onTagToggled;
  final List<Tag> steamTags;

  /// Figures under the notes and tags, such as [GameStat]s.
  final List<Widget> stats;

  /// Rounds the backdrop's top corners to the container's.
  final double cornerRadius;

  /// Width at which the cover sits beside the title, and the notes beside
  /// the tags.
  static const wideBreakpoint = 760.0;

  /// The column's natural height beside the cover at the default text size:
  /// the button row, the title line, the key field and the pills.
  static const _heroInfoHeight = 184.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= wideBreakpoint;
      final divider = Divider(
        height: 40,
        indent: 16,
        endIndent: 16,
        color: theme.border,
      );
      return GameBanner(
        theme: theme,
        coverController: coverController,
        cornerRadius: cornerRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(context, wide),
            divider,
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, stats.isEmpty ? 20 : 0),
              child: _buildBody(context, wide),
            ),
            if (stats.isNotEmpty) ...[
              divider,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Wrap(spacing: 36, runSpacing: 16, children: stats),
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _buildHero(BuildContext context, bool wide) => GameBannerHero(
    theme: theme,
    heading: heading,
    actions: actions,
    wide: wide,
    // The cover keeps its 2:1 shape and ends about level with the pills,
    // growing with the text size.
    coverWidth: math.max(
      CoverImageCard.preferredWidth,
      MediaQuery.textScalerOf(context).scale(_heroInfoHeight) * 2,
    ),
    spacing: 28,
    cover: cover,
    info: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('game-editor-title'),
          controller: titleController,
          maxLines: 2,
          minLines: 1,
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
          decoration: const InputDecoration(hintText: 'Title', isDense: true),
          validator: titleValidator,
          onChanged: onTitleChanged,
          onFieldSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed == value) return;
            titleController.text = trimmed;
            onTitleChanged(trimmed);
          },
        ),
        const SizedBox(height: 10),
        Row(
          spacing: 8,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: keyField),
            platform,
          ],
        ),
        const SizedBox(height: 14),
        Align(alignment: Alignment.centerLeft, child: options),
      ],
    ),
  );

  /// A titled part of the body. An [expand]ed one fills the height it is
  /// given.
  Widget _section(String title, Widget child, {bool expand = false}) => Column(
    mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 10,
    children: [
      Text(
        title,
        style: TextStyle(
          color: theme.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (expand) Expanded(child: child) else child,
    ],
  );

  /// The notes beside the tags; narrow, the notes come first.
  Widget _buildBody(BuildContext context, bool wide) {
    // Beside the tags, the notes fill the height down to the tags' bottom;
    // stacked, they start at five lines and grow as they are typed.
    Widget notesSection({required bool expand}) => _section(
      'Notes',
      expand: expand,
      TextField(
        controller: notesController,
        minLines: expand ? null : 5,
        maxLines: null,
        expands: expand,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(color: theme.textPrimary, height: 1.4),
        decoration: InputDecoration(
          hintText: 'Add notes about this game...',
          hintStyle: TextStyle(color: theme.textHint),
          // Framed like the Multiple Games paste box.
          filled: true,
          fillColor: theme.inputBackground,
          constraints: const BoxConstraints(),
          contentPadding: const EdgeInsets.all(12),
          border: theme.resolveFramedInputBorder(),
        ),
        onChanged: (_) => onNotesChanged(),
      ),
    );
    final tagSection = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 24,
      children: [
        _section(
          'Tags',
          customTags.isEmpty
              ? Text(
                  'No custom tags created yet',
                  style: TextStyle(color: theme.textHint),
                )
              : TagList(
                  tags: customTags,
                  theme: theme,
                  selectedTagIds: selectedTagIds,
                  maxRows: 5,
                  onTagToggled: onTagToggled,
                ),
        ),
        if (steamTags.isNotEmpty)
          _section(
            'Steam Tags',
            TagList(
              tags: steamTags,
              theme: theme,
              allSelected: true,
              maxRows: 5,
            ),
          ),
      ],
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 28,
        children: [notesSection(expand: false), tagSection],
      );
    }
    // The tags set the height and the notes fill it beside them, with room
    // for at least a few lines.
    final minHeight = MediaQuery.textScalerOf(context).scale(180);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 40.0;
        final leftWidth = (constraints.maxWidth - gap) * 3 / 5;
        return Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(left: leftWidth + gap),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: tagSection,
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: leftWidth,
              child: notesSection(expand: true),
            ),
          ],
        );
      },
    );
  }
}

/// The top of a banner: [heading] and [actions] in a row of their own,
/// [info] under them, and [cover] with a drop shadow. Wide, the cover rises
/// beside them to the banner's top; narrow, it sits between them.
class GameBannerHero extends StatelessWidget {
  const GameBannerHero({
    super.key,
    required this.theme,
    this.heading,
    required this.actions,
    required this.cover,
    required this.info,
    required this.wide,
    required this.coverWidth,
    this.spacing = 20,
  });

  final AppThemeData theme;

  /// The dialog's name, at the left of [actions].
  final String? heading;
  final List<Widget> actions;
  final Widget cover;
  final Widget info;
  final bool wide;

  /// The cover's width, and its gap to [info], when [wide].
  final double coverWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final actionRow = BannerHeadingRow(
      theme: theme,
      heading: heading,
      actions: actions,
    );
    final coverBox = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: cover,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 0),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: spacing,
              children: [
                SizedBox(width: coverWidth, child: coverBox),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [actionRow, const SizedBox(height: 4), info],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                actionRow,
                const SizedBox(height: 4),
                coverBox,
                const SizedBox(height: 12),
                info,
              ],
            ),
    );
  }
}

/// [child] over a [GameBannerBackdrop] that runs on under it.
class GameBanner extends StatelessWidget {
  const GameBanner({
    super.key,
    required this.theme,
    required this.child,
    this.coverController,
    this.cornerRadius = 0,
  });

  final AppThemeData theme;
  final Widget child;
  final TextEditingController? coverController;

  /// Rounds the backdrop's top corners to the container's.
  final double cornerRadius;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 0,
        top: 0,
        right: 0,
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(cornerRadius),
          ),
          child: GameBannerBackdrop(
            theme: theme,
            coverController: coverController,
          ),
        ),
      ),
      child,
    ],
  );
}

/// A banner's backdrop: the cover's art blurred and tinted with the accent
/// (so an empty cover still has some colour), fading out over its [height]
/// so it has no edge of its own.
class GameBannerBackdrop extends StatelessWidget {
  const GameBannerBackdrop({
    super.key,
    required this.theme,
    this.coverController,
  });

  final AppThemeData theme;

  /// The cover whose art is blurred in; without one only the tint shows.
  final TextEditingController? coverController;

  /// How far the backdrop reaches down before it has faded out; past it
  /// nothing shows, so nothing is blurred or painted there.
  static const height = 480.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    // The enlarged, blurred art would spill past the fade otherwise.
    child: ClipRect(
      child: RepaintBoundary(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          // Full strength behind the header, then an eased fade to nothing.
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              for (final alpha in [1.0, 1.0, 0.75, 0.4, 0.15, 0.0])
                Colors.white.withValues(alpha: alpha),
            ],
            stops: [
              for (final y in [0, 80, 180, 280, 380, 480]) y / height,
            ],
          ).createShader(bounds),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverController case final cover?)
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: cover,
                  builder: (context, value, _) => value.text.trim().isEmpty
                      ? const SizedBox.shrink()
                      : ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                          child: Transform.scale(
                            scale: 1.4,
                            child: GameCoverImage(
                              theme: theme,
                              coverImage: value.text.trim(),
                            ),
                          ),
                        ),
                ),
              // Dims the art so text stays readable over it.
              ColoredBox(color: theme.background.withValues(alpha: 0.55)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.accent.withValues(alpha: 0.28),
                      theme.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A banner's heading in the accent color, with its buttons at the end. Kept
/// at a button's height when empty, so the content below stays put.
class BannerHeadingRow extends StatelessWidget {
  const BannerHeadingRow({
    super.key,
    required this.theme,
    required this.actions,
    this.heading,
  });

  final AppThemeData theme;
  final String? heading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 40),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      spacing: 8,
      children: [
        if (heading case final heading?)
          Expanded(
            child: DialogHeader(
              title: heading,
              theme: theme,
              titleColor: theme.accent,
            ),
          ),
        ...actions,
      ],
    ),
  );
}

/// The game key's field, its placeholder "Key", or with [playfulHints] a
/// playful line that changes each time the field is emptied.
class GameKeyField extends StatefulWidget {
  const GameKeyField({
    super.key,
    required this.theme,
    required this.controller,
    required this.onChanged,
    this.validator,
    this.isVisible = true,
    this.onVisibilityChanged,
    this.onCopy,
    this.playfulHints = false,
  });

  final AppThemeData theme;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FormFieldValidator<String>? validator;
  final bool isVisible;

  /// Shows a show/hide button when set.
  final ValueChanged<bool>? onVisibilityChanged;

  /// Shows a copy button when set.
  final VoidCallback? onCopy;

  /// Rotates through [hints] in place of the plain "Key" placeholder.
  final bool playfulHints;

  static const hints = [
    'Where did my key go?',
    'No key, no game',
    'XXXXX-XXXXX-XXXXX',
    'Snack? I mean, key please',
    '._.',
  ];

  @override
  State<GameKeyField> createState() => _GameKeyFieldState();
}

class _GameKeyFieldState extends State<GameKeyField> {
  final _random = math.Random();
  late String _hint =
      GameKeyField.hints[_random.nextInt(GameKeyField.hints.length)];
  late bool _empty = widget.controller.text.isEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(GameKeyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onText);
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  /// A key just cleared, by hand or by loading another game, shows a new
  /// placeholder, never the one it had.
  void _onText() {
    final empty = widget.controller.text.isEmpty;
    if (empty && !_empty) {
      final others = [...GameKeyField.hints]..remove(_hint);
      setState(() => _hint = others[_random.nextInt(others.length)]);
    }
    _empty = empty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final visible = widget.isVisible;
    return TextFormField(
      key: const ValueKey('game-editor-key'),
      controller: widget.controller,
      obscureText: !visible,
      style: TextStyle(
        color: theme.textPrimary,
        fontFamily: 'monospace',
        letterSpacing: 1.5,
      ),
      decoration: InputDecoration(
        hintText: widget.playfulHints ? _hint : 'Key',
        hintStyle: TextStyle(color: theme.textHint, letterSpacing: 0),
        suffixIcon: widget.onVisibilityChanged == null && widget.onCopy == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onVisibilityChanged case final onChanged?)
                    IconButton(
                      icon: Icon(
                        visible ? Icons.visibility_off : Icons.visibility,
                        color: theme.textSecondary,
                      ),
                      tooltip: visible ? 'Hide key' : 'Show key',
                      onPressed: () => onChanged(!visible),
                    ),
                  if (widget.onCopy != null)
                    IconButton(
                      icon: Icon(Icons.copy, color: theme.accent),
                      tooltip: 'Copy key',
                      onPressed: widget.onCopy,
                    ),
                ],
              ),
      ),
      validator: widget.validator,
      onChanged: widget.onChanged,
    );
  }
}

/// One figure in the stat strip: an overline, the value and a detail.
class GameStat extends StatelessWidget {
  const GameStat({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    this.fallback = '',
    this.detail,
    this.tooltip,
    this.trailing,
    this.maxLines = 1,
  });

  /// How long ago [date] was, with the day under it and the exact time on
  /// hover.
  factory GameStat.date({
    required AppThemeData theme,
    required String label,
    required DateTime? date,
    String fallback = '',
  }) => GameStat(
    theme: theme,
    label: label,
    value: date == null ? null : daysAgoLabel(date),
    fallback: fallback,
    detail: date == null ? null : _day.format(date),
    tooltip: date == null ? null : _exact.format(date),
  );

  /// The Steam review score with its rating and count, given any reviews.
  /// [compact] leaves the count to the tooltip, so the rating fits beside
  /// another figure on a phone.
  factory GameStat.reviews({
    required AppThemeData theme,
    required int score,
    required int count,
    bool compact = false,
  }) => GameStat(
    theme: theme,
    label: 'Reviews',
    value: count == 0 ? null : '$score%',
    fallback: 'No reviews',
    detail: count == 0
        ? null
        : compact
        ? Game.reviewRatingFor(score)
        : '${Game.reviewRatingFor(score)} · '
              '${NumberFormat.compact().format(count)}',
    tooltip: count == 0 ? null : '$count reviews',
  );

  /// The Steam AppID, with a button to copy it.
  factory GameStat.steamAppId({
    required AppThemeData theme,
    required String appId,
  }) => GameStat(
    theme: theme,
    label: 'Steam AppID',
    value: appId.isEmpty ? null : appId,
    fallback: 'Not set',
    trailing: appId.isEmpty
        ? null
        : IconButton(
            icon: const Icon(Icons.copy, size: 15),
            color: theme.textSecondary,
            // Kept to the value's line height.
            style: IconButton.styleFrom(
              fixedSize: const Size.square(22),
              minimumSize: const Size.square(22),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            tooltip: 'Copy AppID',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: appId));
              NotificationManager.instance.success(
                'Steam AppID copied to clipboard',
              );
            },
          ),
  );

  static final _day = DateFormat('d MMM yyyy');
  static final _exact = DateFormat('dd/MM/yyyy HH:mm');

  final AppThemeData theme;
  final String label;

  /// The figure, or null to show [fallback] muted.
  final String? value;
  final String fallback;
  final String? detail;
  final String? tooltip;
  final Widget? trailing;

  /// Lines the value may take before it is cut short, for names.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: theme.textHint,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Flexible(
              child: Text(
                value ?? fallback,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value == null ? theme.textHint : theme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        if (detail != null)
          Text(detail!, style: TextStyle(color: theme.textHint, fontSize: 12)),
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 110),
      child: tooltip == null
          ? column
          : Tooltip(message: tooltip, child: column),
    );
  }
}
