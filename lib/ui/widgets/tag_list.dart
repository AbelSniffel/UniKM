/// Reusable, performant tag list widget.
///
/// Tags keep Wrap spacing; scrollable lists mount only nearby rows.
///
/// Performance during resize: the scrollable path detects changes to the room
/// it is given, its width or its height limit, via [LayoutBuilder] and hides
/// the Wrap one frame after the change (skipping per-pixel re-layout passes).
/// Once the room has been stable for ~150 ms the Wrap is shown again with a
/// single whole-list fade-in, driven by
/// one [AnimationController] that lives on [_TagListState], rather than
/// starting a separate resize fade for every tag.
///
/// Consolidates tag display and selection patterns across the app in a single
/// optimized widget.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';

import 'package:material_ui/material_ui.dart';
import 'package:unikm/core/constants/app_constants.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import 'app_tag_button.dart';
import 'app_action_button.dart';
import 'app_scrollbar.dart';
import 'app_progress_indicator.dart';

/// A performant, reusable tag list that supports selection, scrolling, and
/// virtualized rendering for large tag collections.
class const TagList({
  super.key,

  /// Tags to display.
  required final List<Tag> tags,

  /// Current app theme.
  required final AppThemeData theme,

  /// Set of selected tag IDs. Chips for these tags appear selected.
  final Set<int>? selectedTagIds,

  /// When true, all tags appear selected. Ignored when [selectedTagIds] is set.
  final bool allSelected = false,

  /// The existing click callback deletes a custom tag rather than filtering it.
  final bool deleteOnTap = false,

  /// Called when a tag chip is tapped. Receives the tag ID.
  final ValueChanged<int>? onTagToggled,

  /// Maximum height for the tag list scroll area. When set, the widget wraps
  /// itself in a [ConstrainedBox] and enables scrolling automatically.
  final double? maxHeight,

  /// Shows at most this many rows of tags and scrolls past them; fewer tags
  /// take only the height they need.
  final int? maxRows,
}) extends StatefulWidget {
  @override
  State<TagList> createState() => _TagListState();
}

class _TagListState extends State<TagList> with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // Resize-aware state (scrollable path only)
  // ---------------------------------------------------------------------------
  Timer? _resizeDebounce;
  // The width and height limit the rows were last shown at.
  Size? _stableRoom;
  bool _tagsVisible = true;
  bool _hidePending = false;
  // Full content height, computed from cached row metrics.
  // Used to preserve the container size while tags are hidden so the
  // layout doesn't collapse or show excess empty space.
  double? _lastKnownHeight;
  // Whether the list last took all the height it was given, as one filling a
  // sidebar does, so the placeholder fills a resized room as well.
  bool _filledRoom = false;
  final _buttons = <int, AppTagButton>{};
  final _textSizes = <String, Size>{};
  // Text style, scaler, direction, locale and whether tags show a mark, that
  // [_textSizes] was measured with.
  Object? _measureMetrics;
  List<Tag> _rowTags = const [];
  double? _rowWidth;
  double _rowHeight = 32;
  List<List<Tag>> _rows = const [];
  List<double> _rowHeights = const [];

  // Single AnimationController driving the whole-list fade-in after resize.
  // One controller for all chips = zero overhead during normal rebuilds.
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  final _scrollController = ScrollController();

  /// Room kept beside the rows for the scrollbar, while the list scrolls.
  static const double _scrollbarGutter = 16;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0, // Start fully visible on first mount.
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _resizeDebounce?.cancel();
    _fadeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TagList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!const ListEquality<Tag>().equals(oldWidget.tags, widget.tags)) {
      final ids = widget.tags.map((tag) => tag.id).toSet();
      final names = widget.tags.map((tag) => tag.name).toSet();
      _buttons.removeWhere((id, _) => !ids.contains(id));
      _textSizes.removeWhere((name, _) => !names.contains(name));
    }
  }

  /// Shows tags again after a resize has settled, triggering the fade-in.
  void _showTags(Size room) {
    if (!mounted) return;
    setState(() {
      _stableRoom = room;
      _tagsVisible = true;
    });
    _fadeController.forward(from: 0.0);
  }

  bool _isSelected(Tag tag) =>
      widget.selectedTagIds?.contains(tag.id) ??
      (widget.onTagToggled == null || widget.allSelected);

  @override
  Widget build(BuildContext context) {
    final tags = widget.tags;
    if (widget.maxHeight != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight!),
        child: _buildScrollableContent(tags),
      );
    }

    if (widget.maxRows != null) {
      return _buildScrollableContent(tags);
    }

    return _buildWrap(tags);
  }

  // ---------------------------------------------------------------------------
  // Scrollable (Wrap inside SingleChildScrollView, resize-aware)
  // ---------------------------------------------------------------------------

  Widget _buildScrollableContent(List<Tag> tags) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth) {
            return SingleChildScrollView(child: _buildWrap(tags));
          }
          final width = constraints.maxWidth;
          // A list that fills the height, as in a sidebar, also refreshes
          // when the window's height changes.
          final room = Size(width, constraints.maxHeight);

          if (_stableRoom == null) {
            // First build — record the stable room, no animation needed.
            _stableRoom = room;
          } else if (room != _stableRoom) {
            // Room changed → hide chips next frame to skip re-layout.
            if (_tagsVisible && !_hidePending) {
              _hidePending = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _hidePending = false;
                if (mounted && _tagsVisible) {
                  setState(() => _tagsVisible = false);
                }
              });
            }
            // Restart debounce: show chips once the room has settled.
            _resizeDebounce?.cancel();
            _resizeDebounce = Timer(
              const Duration(milliseconds: 150),
              () => _showTags(room),
            );
          }

          if (!_tagsVisible) {
            return SizedBox(
              height: _filledRoom && constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : _lastKnownHeight ?? 80.0,
              child: Center(child: AppCircularProgressIndicator(size: 24)),
            );
          }

          // Give the viewport a finite height without shrinkWrap: shrinkWrap
          // would lay out every row and recreate the offscreen button cost.
          final maxRows = widget.maxRows;
          var rows = _layoutRows(context, tags, width);
          double contentHeight() =>
              _rowHeights.fold(0.0, (sum, height) => sum + height) +
              math.max(0, rows.length - 1) * _runSpacing;
          double limit() => math.min(
            constraints.maxHeight,
            maxRows == null || rows.length <= maxRows
                ? double.infinity
                : _rowHeights.take(maxRows).fold(0.0, (sum, h) => sum + h) +
                      (maxRows - 1) * _runSpacing,
          );
          // A list that scrolls wraps clear of its scrollbar.
          final scrolls = contentHeight() > limit();
          if (scrolls) {
            rows = _layoutRows(context, tags, width - _scrollbarGutter);
          }
          final height = contentHeight()
              .clamp(constraints.minHeight, limit())
              .toDouble();
          // The placeholder shown while resizing keeps the height on screen,
          // not the whole list's, so a capped list does not jump open.
          _lastKnownHeight = height;
          _filledRoom = height >= constraints.maxHeight;
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SizedBox(
              height: height,
              // Always shown while the list scrolls, track included.
              child: AppScrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: ListView.custom(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    scrollCacheExtent: ScrollCacheExtent.pixels(
                      _rowHeight + _runSpacing,
                    ),
                    childrenDelegate: _TagRowDelegate(
                      totalExtent: contentHeight(),
                      childCount: rows.length,
                      builder: (context, index) => Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: scrolls ? _scrollbarGutter : 0,
                          bottom: index == rows.length - 1 ? 0 : _runSpacing,
                        ),
                        child: Wrap(
                          spacing: _spacing,
                          children: rows[index].map(_buildButton).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Cache flow layout by text metrics, not theme colors or selection. Only
  /// visible rows mount Material/ink/animation trees; every tag stays reachable.
  List<List<Tag>> _layoutRows(
    BuildContext context,
    List<Tag> tags,
    double width,
  ) {
    final style = Theme.of(context).textTheme.labelLarge!
        .copyWith(color: Colors.black);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    // Only custom tags that a click deletes show a mark, and take its room.
    final marks = widget.deleteOnTap && widget.onTagToggled != null;
    final metrics = (style, scaler, direction, locale, marks);
    final metricsChanged = metrics != _measureMetrics;
    if (metricsChanged) {
      _measureMetrics = metrics;
      _textSizes.clear();
    }
    if (!metricsChanged &&
        width == _rowWidth &&
        const ListEquality<Tag>().equals(tags, _rowTags)) {
      return _rows;
    }
    final painter = TextPainter(
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      maxLines: 1,
    );
    try {
      final rows = <List<Tag>>[];
      final heights = <double>[];
      var row = <Tag>[];
      var rowHeight = 32.0;
      var occupied = 0.0;
      for (final tag in tags) {
        final textSize = _textSizes.putIfAbsent(tag.name, () {
          painter.text = TextSpan(text: tag.name, style: style);
          painter.layout();
          return painter.size;
        });
        final marked = marks && !tag.isSteamTag;
        final tagWidth = math.min(
          width,
          textSize.width +
              AppActionButton.toggleHorizontalPadding * 2 +
              (marked
                  ? AppActionButton.statusSize + AppActionButton.statusSpacing
                  : 0),
        );
        if (row.isNotEmpty && occupied + _spacing + tagWidth > width) {
          rows.add(row);
          heights.add(rowHeight);
          row = [];
          rowHeight = 32;
          occupied = 0;
        }
        occupied += (row.isEmpty ? 0 : _spacing) + tagWidth;
        row.add(tag);
        rowHeight = math.max(
          rowHeight,
          math.max(marked ? AppActionButton.statusSize : 0, textSize.height) +
              14,
        );
      }
      if (row.isNotEmpty) {
        rows.add(row);
        heights.add(rowHeight);
      }
      _rowHeights = heights;
      _rowHeight = heights.fold(32.0, math.max);
      _rowTags = List.of(tags);
      _rowWidth = width;
      _rows = rows;
      return rows;
    } finally {
      painter.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Non-scrollable (plain Wrap)
  // ---------------------------------------------------------------------------

  Widget _buildWrap(List<Tag> tags) => Wrap(
    spacing: _spacing,
    runSpacing: _runSpacing,
    children: tags.map(_buildButton).toList(),
  );

  // ---------------------------------------------------------------------------
  // Button builder
  // ---------------------------------------------------------------------------

  Widget _buildButton(Tag tag) {
    final selected = _isSelected(tag);
    final cached = _buttons[tag.id];
    if (cached != null &&
        cached.tag == tag &&
        cached.deleteOnTap == widget.deleteOnTap &&
        cached.theme == widget.theme &&
        cached.isSelected == selected &&
        (cached.onTap == null) == (widget.onTagToggled == null)) {
      return cached;
    }
    return _buttons[tag.id] = AppTagButton(
      key: ValueKey(tag.id),
      tag: tag,
      theme: widget.theme,
      isSelected: selected,
      deleteOnTap: widget.deleteOnTap,
      onTap: widget.onTagToggled != null
          ? () => widget.onTagToggled?.call(tag.id)
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Layout measurement helpers
  // ---------------------------------------------------------------------------

  static const _spacing = kElementHSpacing;
  static const _runSpacing = kElementVSpacing;
}

/// Supply the exact extent already known from flow layout, so scroll positions
/// do not change as the final (unpadded) row enters the viewport.
class _TagRowDelegate({
  required NullableIndexedWidgetBuilder builder,
  required int childCount,
  required final double totalExtent,
}) extends SliverChildBuilderDelegate {
  this : super(builder, childCount: childCount);

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => totalExtent;
}
