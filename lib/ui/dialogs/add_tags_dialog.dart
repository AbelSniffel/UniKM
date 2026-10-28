/// Create several custom tags without reopening the dialog.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/color_utils.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_search_field.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/tag_list.dart';
import '../widgets/tinted_tiles.dart';
import 'custom_tag_dialogs.dart';

class AddTagsDialog extends ConsumerStatefulWidget {
  const AddTagsDialog({super.key, required this.theme});

  final AppThemeData theme;

  @override
  ConsumerState<AddTagsDialog> createState() => _AddTagsDialogState();
}

class _AddTagsDialogState extends ConsumerState<AddTagsDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _addTag() async {
    if (_saving) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a tag name');
      _focusNode.requestFocus();
      return;
    }
    await _runBusy('Failed to add tag', () async {
      final db = ref.read(requireDatabaseProvider);
      final existing = await db.getTagByName(name);
      if (!mounted) return;
      if (existing != null) {
        setState(
          () => _error = 'A tag named "${existing.name}" already exists',
        );
        return;
      }
      await db.getOrCreateTag(name, color: colorToHex(widget.theme.secondary));
      if (!mounted) return;
      await ref.read(tagsProvider.notifier).refresh();
      await persistEncryptedDbIfNeeded(ref, database: db);
      if (!mounted) return;
      // Preserve the next name if the user typed while this tag was saving.
      if (_controller.text.trim() == name) _controller.clear();
    });
  }

  Future<void> _deleteTag(int tagId, String tagName) => _runBusy(
    'Failed to delete tag',
    () => deleteTagWithConfirmation(
      context: context,
      theme: widget.theme,
      tagId: tagId,
      tagName: tagName,
    ),
  );

  Future<void> _deleteAllCustomTags() => _runBusy(
    'Failed to delete tags',
    () => deleteAllCustomTagsWithConfirmation(
      context: context,
      theme: widget.theme,
    ),
  );

  /// Blocks other tag actions while [action] runs, shows any failure inline,
  /// and returns focus to the name field afterwards.
  Future<void> _runBusy(
    String failureMessage,
    Future<void> Function() action,
  ) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '$failureMessage: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _focusNode.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final tags = ref.watch(customTagsProvider);
    return PopScope(
      canPop: !_saving,
      child: DialogInteractionScope(
        onPrimaryAction: _addTag,
        enableEscapeDismiss: !_saving,
        child: ThemedAlertDialog(
          theme: theme,
          showCloseButton: false,
          titleActions: [
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
            ),
          ],
          maxWidth: 520,
          title: DialogHeader(
            icon: Icons.label_outline,
            title: 'Add Tags',
            theme: theme,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: AppSearchField(
                          theme: theme,
                          controller: _controller,
                          focusNode: _focusNode,
                          hintText: 'Enter tag name...',
                          prefixIcon: Icons.label_outline,
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                          onSubmitted: (_) => _addTag(),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _saving ? null : _addTag,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Text(_error!, style: TextStyle(color: theme.error)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  TintedHeading(
                    theme: theme,
                    title: 'Custom Tags',
                    trailing: '${tags.length}',
                    // Keep the heading's height as the first or last tag
                    // comes and goes.
                    action: Visibility(
                      visible: tags.isNotEmpty,
                      maintainSize: true,
                      maintainState: true,
                      maintainAnimation: true,
                      child: IconButton(
                        tooltip: 'Delete All Custom Tags',
                        visualDensity: VisualDensity.compact,
                        onPressed: _saving || tags.isEmpty
                            ? null
                            : _deleteAllCustomTags,
                        icon: const Icon(Icons.delete_sweep_outlined),
                        color: theme.error,
                      ),
                    ),
                  ),
                  Container(
                    key: const ValueKey('custom-tags-panel'),
                    height: 220,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(theme.cornerRadius),
                      border: Border.all(color: theme.border),
                    ),
                    child: tags.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 8,
                              children: [
                                Icon(
                                  Icons.label_off_outlined,
                                  color: theme.textHint,
                                  size: 32,
                                ),
                                Text(
                                  'No custom tags created yet',
                                  style: TextStyle(color: theme.textHint),
                                ),
                              ],
                            ),
                          )
                        : TagList(
                            tags: tags,
                            theme: theme,
                            allSelected: true,
                            deleteOnTap: true,
                            scrollable: true,
                            onTagToggled: (tagId) {
                              final tag = tags.firstWhere(
                                (tag) => tag.id == tagId,
                              );
                              _deleteTag(tag.id, tag.name);
                            },
                          ),
                  ),
                  Text(
                    'Tap a tag to delete it.',
                    style: TextStyle(color: theme.textHint, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
