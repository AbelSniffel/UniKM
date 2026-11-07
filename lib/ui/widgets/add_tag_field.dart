import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/color_utils.dart';
import '../../providers/app_providers.dart';
import 'app_search_field.dart';

/// A tag name field and Add button that create custom tags one after
/// another, keeping the field focused for the next name.
class AddTagField extends ConsumerStatefulWidget {
  const AddTagField({super.key, required this.theme});

  final AppThemeData theme;

  @override
  ConsumerState<AddTagField> createState() => _AddTagFieldState();
}

class _AddTagFieldState extends ConsumerState<AddTagField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _addTag() async {
    if (_saving) return;
    final name = _controller.text.trim();
    _focusNode.requestFocus();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a tag name');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final db = ref.read(requireDatabaseProvider);
      final existing = await db.getTagByName(name);
      if (existing != null) {
        if (mounted) {
          setState(
            () => _error = 'A tag named "${existing.name}" already exists',
          );
        }
        return;
      }
      await db.getOrCreateTag(name, color: colorToHex(widget.theme.secondary));
      await ref.read(tagsProvider.notifier).refresh();
      await persistEncryptedDbIfNeeded(ref, database: db);
      // Keep a next name typed while this tag was saving.
      if (mounted && _controller.text.trim() == name) _controller.clear();
    } catch (error) {
      if (mounted) setState(() => _error = 'Failed to add tag: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      Row(
        spacing: 8,
        children: [
          Expanded(
            child: AppSearchField(
              theme: widget.theme,
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
        Text(_error!, style: TextStyle(color: widget.theme.error)),
    ],
  );
}
