/// Reusable, performant tag list widget.
///
/// All paths use [Wrap] for correct layout (accurate chip widths, no overflow).
///
/// Performance during resize: the scrollable path detects horizontal width
/// changes via [LayoutBuilder] and hides the Wrap one frame after the change
/// (skipping per-pixel re-layout passes). Once the width has been stable for
/// ~150 ms the Wrap is shown again with a single whole-list fade-in, driven by
/// one [AnimationController] that lives on [_TagListState] — zero per-chip
/// controllers means zero overhead during normal redraws.
///
/// Consolidates tag display and selection patterns across the app in a single
/// optimized widget.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unikm/core/constants/app_constants.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import 'app_search_field.dart';
import 'app_tag_chip.dart';
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
  // Actual rendered height of the Wrap content, measured post-frame.
  // Used to preserve the container size while tags are hidden so the
  // layout doesn't collapse or show excess empty space.
  double? _lastKnownHeight;
  // Key attached to the Wrap so we can read its RenderBox height after layout.
  final GlobalKey _wrapKey = GlobalKey();

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
    return widget.allSelected;
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

          // Single FadeTransition over the entire Wrap — one controller for
          // the whole list, no per-chip animation overhead on redraws.
          //
          // Measure the Wrap's actual rendered height after this frame so that
          // when tags are hidden we preserve the real content height (not the
          // max-constraint height which makes short lists look too tall).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_tagsVisible) return;
            final box =
                _wrapKey.currentContext?.findRenderObject() as RenderBox?;
            if (box != null && box.hasSize && box.size.height > 0) {
              _lastKnownHeight = box.size.height;
            }
          });

          return FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              child: Wrap(
                key: _wrapKey,
                spacing: _spacing,
                runSpacing: _runSpacing,
                children: tags.map(_buildChip).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Non-scrollable (plain Wrap)
  // ---------------------------------------------------------------------------

  Widget _buildWrap(List<Tag> tags) {
    return Wrap(
      spacing: _spacing,
      runSpacing: _runSpacing,
      children: tags.map(_buildChip).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Chip builder
  // ---------------------------------------------------------------------------

  Widget _buildChip(Tag tag) {
    return AppTagChip(
      key: ValueKey(tag.id),
      tag: tag,
      theme: widget.theme,
      isSelected: _isSelected(tag),
      onTap: widget.onTagToggled != null
          ? () => widget.onTagToggled!(tag.id)
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Layout measurement helpers
  // ---------------------------------------------------------------------------

  static const _spacing = kElementHSpacing;
  static const _runSpacing = kElementVSpacing;
}
