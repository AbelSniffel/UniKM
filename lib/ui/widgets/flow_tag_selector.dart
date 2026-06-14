/// Flow layout for tags with search
/// Matches the original Python FlowTagSelector
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import 'app_search_field.dart';
import 'app_tag_chip.dart';

/// Flow layout tag selector with search
class FlowTagSelector extends StatefulWidget {
  const FlowTagSelector({
    super.key,
    required this.tags,
    required this.selectedTagIds,
    this.onTagToggled,
    required this.theme,
    this.showSearch = true,
    this.maxHeight,
  });

  final List<Tag> tags;
  final Set<int> selectedTagIds;
  final ValueChanged<int>? onTagToggled;
  final AppThemeData theme;
  final bool showSearch;
  final double? maxHeight;

  @override
  State<FlowTagSelector> createState() => _FlowTagSelectorState();
}

class _FlowTagSelectorState extends State<FlowTagSelector> {
  String _searchQuery = '';

  List<Tag> get _filteredTags {
    if (_searchQuery.isEmpty) return widget.tags;
    return widget.tags
        .where((t) => t.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showSearch) ...[
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
        ],

        Expanded(
          child: Container(
            constraints: widget.maxHeight != null
                ? BoxConstraints(maxHeight: widget.maxHeight!)
                : null,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _filteredTags.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tag = entry.value;
                  return _AnimatedTagChip(
                    key: ValueKey(tag.id),
                    tag: tag,
                    isSelected: widget.selectedTagIds.contains(tag.id),
                    onTap: widget.onTagToggled != null
                        ? () => widget.onTagToggled!(tag.id)
                        : null,
                    theme: widget.theme,
                    staggerDelay: Duration(milliseconds: index * 20),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A tag chip that plays a single fade-in/scale intro animation when first
/// mounted, then stays static for the rest of its lifetime.
///
/// Using [ValueKey] with the tag ID on this widget ensures Flutter reuses the
/// existing element and its [State] across parent rebuilds (e.g. every frame
/// during window resize). The animation controller is therefore only created
/// once and completes once — it is never restarted by a parent rebuild — which
/// eliminates the per-frame animation churn that caused visible lag when the
/// previous approach applied `flutter_animate` directly inside the parent's
/// `build` method.
class _AnimatedTagChip extends StatefulWidget {
  const _AnimatedTagChip({
    super.key,
    required this.tag,
    required this.isSelected,
    required this.theme,
    this.onTap,
    this.staggerDelay = Duration.zero,
  });

  final Tag tag;
  final bool isSelected;
  final AppThemeData theme;
  final VoidCallback? onTap;
  /// Delay before the intro animation starts. Only respected on first mount — 
  /// parent rebuilds reuse existing State via [ValueKey], so this never fires
  /// again after the chip is initially shown.
  final Duration staggerDelay;

  @override
  State<_AnimatedTagChip> createState() => _AnimatedTagChipState();
}

class _AnimatedTagChipState extends State<_AnimatedTagChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    if (widget.staggerDelay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.staggerDelay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: AppTagChip(
            tag: widget.tag,
            isSelected: widget.isSelected,
            onTap: widget.onTap,
            theme: widget.theme,
          ),
        ),
      ),
    );
  }
}
