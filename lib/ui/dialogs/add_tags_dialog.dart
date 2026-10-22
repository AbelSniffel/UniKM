/// Create several custom tags without reopening the dialog.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/color_utils.dart';
import '../../providers/app_providers.dart';
import '../widgets/app_search_field.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/tag_list.dart';
import '../widgets/section_groupbox.dart';
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
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
    } catch (error) {
      if (mounted) setState(() => _error = 'Failed to add tag: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _focusNode.requestFocus();
      }
    }
  }

  Future<void> _deleteTag(int tagId, String tagName) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await deleteTagWithConfirmation(
        context: context,
        theme: widget.theme,
        tagId: tagId,
        tagName: tagName,
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Failed to delete tag: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _focusNode.requestFocus();
      }
    }
  }

  Future<void> _deleteAllCustomTags() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await deleteAllCustomTagsWithConfirmation(
        context: context,
        theme: widget.theme,
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Failed to delete tags: $error');
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
    final tags = ref
        .watch(tagsProvider)
        .where((tag) => !tag.isSteamTag)
        .toList();
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
            children: [
              Text(
                'Create custom tags or click a tag to delete it.',
                style: TextStyle(color: theme.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
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
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _addTag,
                    child: const Text('Add'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.error)),
              ],
              const SizedBox(height: 16),
              SectionGroupBox(
                title: 'Custom Tags (${tags.length})',
                titleIcon: Icons.label,
                titleLocation: SectionTitleLocation.top,
                theme: theme,
                headerCrossAxisAlignment: CrossAxisAlignment.center,
                // Keep the header's height stable as the first/last tag changes.
                trailing: Visibility(
                  visible: tags.isNotEmpty,
                  maintainSize: true,
                  maintainState: true,
                  maintainAnimation: true,
                  child: IconButton(
                    tooltip: 'Delete All Custom Tags',
                    onPressed: _saving || tags.isEmpty
                        ? null
                        : _deleteAllCustomTags,
                    icon: const Icon(Icons.delete, size: 26),
                    color: theme.error,
                  ),
                ),
                child: SizedBox(
                  height: 220,
                  child: tags.isEmpty
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            'No custom tags created yet',
                            style: TextStyle(color: theme.textHint),
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
