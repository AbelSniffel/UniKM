/// The layout both game editors share, styled like a store page.
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/constants/platform_patterns.dart';
import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import 'cover_image_card.dart';
import 'dialog_helpers.dart';
import 'game_cover_image.dart';
import 'notification_system.dart';
import 'platform_icon.dart';
import 'tag_list.dart';

/// How long ago [date] was, in whole days, months or years.
String daysAgoLabel(DateTime date) {
  final days = DateUtils.dateOnly(DateTime.now())
      .difference(DateUtils.dateOnly(date))
      .inDays;
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
class const GameEditorLayout({
  super.key,
  required final AppThemeData theme,

  /// The cover card, and the path its art is drawn from behind the banner.
  required final Widget cover,
  required final TextEditingController coverController,

  /// Buttons for the top right of the banner.
  required final List<Widget> actions,

  /// The dialog's name, at the left of [actions].
  final String? heading,
  required final TextEditingController titleController,
  required final ValueChanged<String> onTitleChanged,
  final FormFieldValidator<String>? titleValidator,
  required final Widget keyField,
  required final Widget platform,
  required final Widget options,
  required final TextEditingController notesController,
  required final VoidCallback onNotesChanged,
  required final List<Tag> customTags,
  required final Set<int> selectedTagIds,
  required final ValueChanged<int> onTagToggled,
  required final List<Tag> steamTags,

  /// Figures under the notes and tags, such as [GameStat]s.
  final List<Widget> stats = const [],

  /// Rounds the backdrop's top corners to the container's.
  final double cornerRadius = 0,
}) extends StatelessWidget {
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
        coverController: coverController,
        cornerRadius: cornerRadius,
        solidHeight: GameBannerBackdrop.solidHeightFor(
          wide: wide,
          width: constraints.maxWidth,
          coverAspect: 2,
        ),
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

  /// From the notes' frame to what it holds, as in [GameTagsBox].
  static const _boxPadding = 12.0;

  /// Between the notes and the tags, beside or above each other, as between
  /// the deadline picker's two fields.
  static const _notesTagsGap = 12.0;

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
          // Framed like the Multiple Games paste box, but rounded like the
          // tags' box beside it.
          filled: true,
          fillColor: theme.inputBackground,
          constraints: const BoxConstraints(),
          contentPadding: const EdgeInsets.all(_boxPadding),
          border: theme.resolveFramedInputBorder(radius: theme.panelRadius),
        ),
        onChanged: (_) => onNotesChanged(),
      ),
    );
    final tagSection = _section(
      'Tags',
      GameTagsBox(
        custom: customTags.isEmpty
            // Centred on the icon, like a row of tags.
            ? ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Align(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  child: Text(
                    'No custom tags created yet',
                    style: TextStyle(color: theme.textHint),
                  ),
                ),
              )
            : TagList(
                tags: customTags,
                theme: theme,
                selectedTagIds: selectedTagIds,
                maxRows: 5,
                onTagToggled: onTagToggled,
              ),
        steamTags: steamTags,
      ),
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: _notesTagsGap,
        children: [notesSection(expand: false), tagSection],
      );
    }
    // The tags set the height and the notes fill it beside them, with room
    // for at least a few lines.
    final minHeight = MediaQuery.textScalerOf(context).scale(180);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = _notesTagsGap;
        // An even split: notes are usually short and have the height to grow
        // into, so the tags get as much room.
        final leftWidth = (constraints.maxWidth - gap) / 2;
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
/// [info] under them, and [cover]. Wide, the cover rises beside them to the
/// banner's top; narrow, it sits between them.
class const GameBannerHero({
  super.key,

  /// The dialog's name, at the left of [actions].
  final String? heading,
  required final List<Widget> actions,
  required final Widget cover,
  required final Widget info,
  required final bool wide,

  /// The cover's width, and its gap to [info], when [wide].
  required final double coverWidth,
  final double spacing = 20,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actionRow = BannerHeadingRow(heading: heading, actions: actions);
    return Padding(
      // As far from the top as the buttons are from the bottom, so the
      // cover's corner curves with the dialog's.
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 0),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: spacing,
              children: [
                SizedBox(width: coverWidth, child: cover),
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
                cover,
                const SizedBox(height: 12),
                info,
              ],
            ),
    );
  }
}

/// [child] over a [GameBannerBackdrop] that runs on under it.
class const GameBanner({
  super.key,
  required final Widget child,
  final TextEditingController? coverController,

  /// Rounds the backdrop's top corners to the container's.
  final double cornerRadius = 0,

  /// How far down the backdrop stays at full strength.
  final double solidHeight = GameBannerBackdrop.headerHeight,
}) extends StatelessWidget {
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
            coverController: coverController,
            solidHeight: solidHeight,
          ),
        ),
      ),
      child,
    ],
  );
}

/// A banner's backdrop: the cover's art blurred and tinted with the accent
/// (so an empty cover still has some colour), at full strength down to
/// [solidHeight], then fading out over [fadeLength] so it has no edge of its
/// own.
class const GameBannerBackdrop({
  super.key,

  /// The cover whose art is blurred in; without one only the tint shows.
  final TextEditingController? coverController,

  /// How far down the backdrop stays at full strength.
  final double solidHeight = headerHeight,
}) extends StatelessWidget {
  /// Full strength behind a banner's heading row.
  static const headerHeight = 80.0;

  /// How far the backdrop fades out below [solidHeight]; past it nothing
  /// shows, so nothing is blurred or painted there.
  static const fadeLength = 400.0;

  /// The full-strength height for a [GameBannerHero] [width] wide whose
  /// cover is [coverAspect] wide for its height. Wide, the cover sits beside
  /// the details and only the heading needs it; narrow, the cover spans the
  /// banner and would hide that part, so it reaches down to the cover's foot
  /// and the art shows round the details under it.
  static double solidHeightFor({
    required bool wide,
    required double width,
    required double coverAspect,
  }) => wide
      ? headerHeight
      // The hero's padding (12 and 10 at the sides, 12 on top), heading row
      // (40) and the 4 under it.
      : 56 + (width - 22) / coverAspect;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final height = solidHeight + fadeLength;
    return SizedBox(
      height: height,
      // The enlarged, blurred art would spill past the fade otherwise.
      child: ClipRect(
        child: RepaintBoundary(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            // Full strength down to [solidHeight], then an eased fade to
            // nothing.
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                for (final alpha in [1.0, 1.0, 0.75, 0.4, 0.15, 0.0])
                  Colors.white.withValues(alpha: alpha),
              ],
              stops: [
                0,
                for (final y in [0, 100, 200, 300, 400])
                  (solidHeight + y) / height,
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
                            imageFilter: ImageFilter.blur(
                              sigmaX: 40,
                              sigmaY: 40,
                            ),
                            child: Transform.scale(
                              scale: 1.4,
                              child: GameCoverImage(
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
}

/// A banner's heading in the accent color, with its buttons at the end. Kept
/// at a button's height when empty, so the content below stays put.
class const BannerHeadingRow({
  super.key,
  required final List<Widget> actions,
  final String? heading,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: 8,
        children: [
          if (heading case final heading?)
            Expanded(
              child: DialogHeader(title: heading, titleColor: theme.accent),
            ),
          ...actions,
        ],
      ),
    );
  }
}

/// The game key's field, its placeholder "Key", or with [playfulHints] a
/// playful line that changes each time the field is emptied.
class const GameKeyField({
  super.key,
  required final TextEditingController controller,
  required final ValueChanged<String> onChanged,
  final FormFieldValidator<String>? validator,
  final bool isVisible = true,

  /// Shows a show/hide button when set.
  final ValueChanged<bool>? onVisibilityChanged,

  /// Shows a copy button when set.
  final VoidCallback? onCopy,

  /// Rotates through [hints] in place of the plain "Key" placeholder.
  final bool playfulHints = false,
}) extends StatefulWidget {
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
    final theme = context.appTheme;
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

/// Tags in a box outlined like the Game Editor's Notes, but unfilled so the
/// banner's art shows through, curving with the tags 12 px in: [custom] tags
/// beside a pencil, then [steamTags] beside the Steam icon, as one list.
class const GameTagsBox({
  super.key,
  final Widget? custom,
  final List<Tag> steamTags = const [],
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final radius = BorderRadius.circular(theme.panelRadius);
    // As wide for either icon, so both lists start in line, and level with
    // the first row of tags.
    Widget labelled(String label, Widget icon, Widget tags) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        SizedBox(
          width: 22,
          height: 32,
          child: Tooltip(
            message: label,
            child: Center(child: icon),
          ),
        ),
        Expanded(child: tags),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.border),
        borderRadius: radius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        // A little further apart than rows of tags, so each kind starts a
        // group of its own.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            if (custom case final custom?)
              labelled(
                'Custom Tags',
                Icon(Icons.edit, size: 18, color: theme.textSecondary),
                custom,
              ),
            if (steamTags.isNotEmpty)
              labelled(
                'Steam Tags',
                PlatformIcon(
                  platform: GamePlatform.steam,
                  color: theme.textSecondary,
                ),
                TagList(
                  tags: steamTags,
                  theme: theme,
                  allSelected: true,
                  maxRows: 5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One figure in the stat strip: an overline, the value and a detail.
class const GameStat({
  super.key,
  required final AppThemeData theme,
  required final String label,

  /// The figure, or null to show [fallback] muted.
  required final String? value,
  final String fallback = '',
  final String? detail,
  final String? tooltip,
  final Widget? trailing,

  /// Lines the value may take before it is cut short, for names.
  final int maxLines = 1,
}) extends StatelessWidget {
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
