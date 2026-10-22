/// Reusable, performant tag list widget.
///
/// Tags keep Wrap spacing; scrollable lists mount only nearby rows.
///
/// Performance during resize: the scrollable path detects horizontal width
/// changes via [LayoutBuilder] and hides the Wrap one frame after the change
/// (skipping per-pixel re-layout passes). Once the width has been stable for
/// ~150 ms the Wrap is shown again with a single whole-list fade-in, driven by
/// one [AnimationController] that lives on [_TagListState], rather than
/// starting a separate resize fade for every tag.
///
/// Consolidates tag display and selection patterns across the app in a single
/// optimized widget.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:unikm/core/constants/app_constants.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import 'app_search_field.dart';
import 'app_tag_button.dart';
import 'app_action_button.dart';
import 'app_progress_indicator.dart';

/// A performant, reusable tag list that supports search, selection,
/// scrolling, and virtualized rendering for large tag collections.
class TagList extends StatefulWidget {
  const TagList({
    super.key,
    required this.tags,
    required this.theme,
    this.selectedTagIds,
    this.allSelected = false,
    this.deleteOnTap = false,
    this.onTagToggled,
    this.showSearch = false,
    this.maxHeight,
    this.scrollable = false,
  });

  /// Tags to display.
  final List<Tag> tags;

  /// Current app theme.
  final AppThemeData theme;

  /// Set of selected tag IDs. Chips for these tags appear selected.
  final Set<int>? selectedTagIds;

  /// When true, all tags appear selected. Ignored when [selectedTagIds] is set.
  final bool allSelected;

  /// The existing click callback deletes a custom tag rather than filtering it.
  final bool deleteOnTap;

  /// Called when a tag chip is tapped. Receives the tag ID.
  final ValueChanged<int>? onTagToggled;

  /// Whether to show a search field above the tag list.
  /// When true, the widget must be placed inside a parent with bounded height
  /// constraints (e.g. [SizedBox], [ConstrainedBox], or [Expanded]).
  final bool showSearch;

  /// Maximum height for the tag list scroll area. When set, the widget wraps
  /// itself in a [ConstrainedBox] and enables scrolling automatically.
  final double? maxHeight;

  /// When true, the tag list scrolls inside whatever height the parent provides.
  /// Use this when the parent already constrains the height (e.g. via
  /// [Expanded]) and no explicit [maxHeight] is needed.
  final bool scrollable;

  @override
  State<TagList> createState() => _TagListState();
}

class _TagListState extends State<TagList> with SingleTickerProviderStateMixin {
  String _searchQuery = '';

  // ---------------------------------------------------------------------------
  // Resize-aware state (scrollable path only)
  // ---------------------------------------------------------------------------
  Timer? _resizeDebounce;
  double? _stableWidth;
  bool _tagsVisible = true;
  bool _hidePending = false;
  // Full content height, computed from cached row metrics.
  // Used to preserve the container size while tags are hidden so the
  // layout doesn't collapse or show excess empty space.
  double? _lastKnownHeight;
  final _buttons = <int, AppTagButton>{};
  final _textSizes = <String, Size>{};
  TextStyle? _measureStyle;
  TextScaler? _measureScaler;
  TextDirection? _measureDirection;
  Locale? _measureLocale;
  bool? _measureStatusHidden;
  List<Tag> _rowTags = const [];
  double? _rowWidth;
  double _rowHeight = 32;
  List<List<Tag>> _rows = const [];
  List<double> _rowHeights = const [];

  // Single AnimationController driving the whole-list fade-in after resize.
  // One controller for all chips = zero overhead during normal rebuilds.
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

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
  void _showTags(double newWidth) {
    if (!mounted) return;
    setState(() {
      _stableWidth = newWidth;
      _tagsVisible = true;
    });
    _fadeController.forward(from: 0.0);
  }

  List<Tag> get _filteredTags {
    if (_searchQuery.isEmpty) return widget.tags;
    final query = _searchQuery.toLowerCase();
    return widget.tags
        .where((t) => t.name.toLowerCase().contains(query))
        .toList();
  }

  bool _isSelected(Tag tag) {
    if (widget.selectedTagIds != null) {
      return widget.selectedTagIds!.contains(tag.id);
    }
    return widget.onTagToggled == null || widget.allSelected;
  }

  @override
  Widget build(BuildContext context) {
    final tags = _filteredTags;

    if (widget.showSearch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            theme: widget.theme,
            hintText: 'Search tags...',
            onChanged: (value) => setState(() => _searchQuery = value),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildScrollableContent(tags)),
        ],
      );
    }

    if (widget.maxHeight != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight!),
        child: _buildScrollableContent(tags),
      );
    }

    if (widget.scrollable) {
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

          if (_stableWidth == null) {
            // First build — record stable width, no animation needed.
            _stableWidth = width;
          } else if (width != _stableWidth) {
            // Width changed → hide chips next frame to skip Wrap re-layout.
            if (_tagsVisible && !_hidePending) {
              _hidePending = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _hidePending = false;
                if (mounted && _tagsVisible) {
                  setState(() => _tagsVisible = false);
                }
              });
            }
            // Restart debounce: show chips once width has settled.
            _resizeDebounce?.cancel();
            _resizeDebounce = Timer(const Duration(milliseconds: 150), () {
              _showTags(width);
            });
          }

          final preservedHeight = _lastKnownHeight ?? 80.0;

          if (!_tagsVisible) {
            return SizedBox(
              height: preservedHeight,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: AppCircularProgressIndicator(),
                ),
              ),
            );
          }

          final rows = _layoutRows(context, tags, width);
          final contentHeight =
              _rowHeights.fold(0.0, (sum, height) => sum + height) +
              math.max(0, rows.length - 1) * _runSpacing;
          _lastKnownHeight = contentHeight;
          // Give the viewport a finite height without shrinkWrap: shrinkWrap
          // would lay out every row and recreate the offscreen button cost.
          final height = contentHeight.clamp(
            constraints.minHeight,
            constraints.maxHeight,
          );
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SizedBox(
              height: height,
              child: ListView.custom(
                padding: EdgeInsets.zero,
                scrollCacheExtent: ScrollCacheExtent.pixels(
                  _rowHeight + _runSpacing,
                ),
                childrenDelegate: _TagRowDelegate(
                  totalExtent: contentHeight,
                  childCount: rows.length,
                  builder: (context, index) => Padding(
                    padding: EdgeInsets.only(
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
          );
        },
      ),
    );
  }

  /// Cache flow layout by text metrics, not theme colors or selection. Only
  /// visible rows mount Material/ink/animation trees; every tag stays searchable.
  List<List<Tag>> _layoutRows(
    BuildContext context,
    List<Tag> tags,
    double width,
  ) {
    final style = Theme.of(
      context,
    ).textTheme.labelLarge!.copyWith(color: Colors.black);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final statusHidden = widget.onTagToggled == null;
    final metricsChanged =
        style != _measureStyle ||
        scaler != _measureScaler ||
        direction != _measureDirection ||
        locale != _measureLocale ||
        statusHidden != _measureStatusHidden;
    if (metricsChanged) {
      _measureStyle = style;
      _measureScaler = scaler;
      _measureDirection = direction;
      _measureLocale = locale;
      _measureStatusHidden = statusHidden;
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
        final tagWidth = math.min(
          width,
          textSize.width +
              AppActionButton.toggleHorizontalPadding * 2 +
              (statusHidden
                  ? 0
                  : AppActionButton.statusSize + AppActionButton.statusSpacing),
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
          math.max(
                statusHidden ? 0 : AppActionButton.statusSize,
                textSize.height,
              ) +
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

  Widget _buildWrap(List<Tag> tags) {
    return Wrap(
      spacing: _spacing,
      runSpacing: _runSpacing,
      children: tags.map(_buildButton).toList(),
    );
  }

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
class _TagRowDelegate extends SliverChildBuilderDelegate {
  _TagRowDelegate({
    required NullableIndexedWidgetBuilder builder,
    required int childCount,
    required this.totalExtent,
  }) : super(builder, childCount: childCount);

  final double totalExtent;

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => totalExtent;
}
