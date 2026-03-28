/// Flow layout for tags with search
/// Matches the original Python FlowTagSelector
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

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
                  final isSelected = widget.selectedTagIds.contains(tag.id);

                  return AppTagChip(
                        tag: tag,
                        isSelected: isSelected,
                        onTap: widget.onTagToggled != null
                            ? () => widget.onTagToggled!(tag.id)
                            : null,
                        theme: widget.theme,
                      )
                      .animate(delay: Duration(milliseconds: index * 20))
                      .fadeIn(duration: const Duration(milliseconds: 200))
                      .scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1, 1),
                        duration: const Duration(milliseconds: 200),
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
