/// Flow layout for tags with search
/// Matches the original Python FlowTagSelector
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../models/game.dart';
import 'app_search_field.dart';

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
            showClearButton: false,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                spacing: 8,
                runSpacing: 8,
                children: _filteredTags.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tag = entry.value;
                  final isSelected = widget.selectedTagIds.contains(tag.id);
                  
                  return _TagChip(
                    tag: tag,
                    isSelected: isSelected,
                    onTap: widget.onTagToggled != null 
                        ? () => widget.onTagToggled!(tag.id) 
                        : null,
                    theme: widget.theme,
                  ).animate(delay: Duration(milliseconds: index * 20))
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

class _TagChip extends StatefulWidget {
  const _TagChip({
    required this.tag,
    required this.isSelected,
    this.onTap,
    required this.theme,
  });

  final Tag tag;
  final bool isSelected;
  final VoidCallback? onTap;
  final AppThemeData theme;

  @override
  State<_TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<_TagChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null;
    
    return MouseRegion(
      onEnter: isEnabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: isEnabled ? (_) => setState(() => _isHovered = false) : null,
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            // Steam tags use accent color; custom tags use primary color.
            // Selected and hover states tint with the respective base color.
            color: (() {
              final isSteam = widget.tag.isSteamTag;
              final baseColor = isSteam ? widget.theme.accent : widget.theme.primary;
              if (widget.isSelected) return baseColor;
              if (_isHovered) return baseColor.withValues(alpha: 0.12);
              return widget.theme.tagBackground;
            })(),
            borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
            border: Border.all(
              color: (() {
                final isSteam = widget.tag.isSteamTag;
                final baseColor = isSteam ? widget.theme.accent : widget.theme.primary;
                if (widget.isSelected) return baseColor;
                return baseColor.withValues(alpha: 0.5);
              })(),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isSelected) ...[
                Icon(
                  Icons.check,
                  size: 14,
                  color: widget.theme.primaryButtonText,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                widget.tag.name,
                style: TextStyle(
                  color: widget.isSelected
                      ? widget.theme.primaryButtonText
                      : widget.theme.textPrimary,
                  fontSize: 12,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple tag display chip (non-interactive)
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.tag,
    required this.theme,
    this.onRemove,
    this.isSelected = false,
  });

  final Tag tag;
  final AppThemeData theme;
  final VoidCallback? onRemove;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final isSteam = tag.isSteamTag;
    final baseColor = isSteam ? theme.accent : theme.primary;
    final bg = isSelected ? baseColor : theme.tagBackground;
    final borderCol = isSelected ? baseColor : baseColor.withValues(alpha: 0.6);
    final textCol = isSelected ? theme.primaryButtonText : theme.textPrimary;

    return Container(
      padding: EdgeInsets.only(
        left: 10,
        right: onRemove != null ? 4 : 10,
        top: 4,
        bottom: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected) ...[
            Icon(Icons.check, size: 14, color: textCol),
            const SizedBox(width: 6),
          ],
          Text(
            tag.name,
            style: TextStyle(
              color: textCol,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: Icon(
                Icons.close,
                size: 14,
                color: textCol.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
