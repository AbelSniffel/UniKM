import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/device_sync_models.dart';
import '../../providers/app_providers.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/pair_code_widgets.dart';

enum IncomingPairDialogResult { declined, resolved }

/// Dialog shown on the receiver side when an incoming pair request arrives.
///
/// Both devices show the same code, derived from both devices' keys, only
/// when nothing between them swapped those keys. The user checks that the
/// codes match and pairs, or declines. Closes on its own when pairing
/// completes, is canceled on the other device, or times out.
class IncomingPairDialog extends ConsumerStatefulWidget {
  const IncomingPairDialog({super.key, required this.request});
  final PendingPairRequest request;

  @override
  ConsumerState<IncomingPairDialog> createState() => _IncomingPairDialogState();
}

class _IncomingPairDialogState extends ConsumerState<IncomingPairDialog> {
  bool _accepted = false;
  String? _error;
  StreamSubscription<SyncEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _eventSub = ref.read(deviceSyncServiceProvider).syncEvents.listen((event) {
      final shouldClose = switch (event) {
        PairRequestCanceledEvent(:final request) ||
        PairRequestTimedOutEvent(
          :final request,
        ) => request.requestId == widget.request.requestId,
        PeerTrustedEvent(:final peer) => peer.id == widget.request.peer.id,
        _ => false,
      };
      if (shouldClose && mounted) {
        Navigator.of(context).maybePop(IncomingPairDialogResult.resolved);
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final peer = widget.request.peer;
    return DialogInteractionScope(
      onPrimaryAction: _accepted ? null : _accept,
      onDismiss: _accepted ? null : _decline,
      child: ThemedAlertDialog(
        theme: theme,
        title: DialogHeader(
          icon: Icons.handshake,
          title: 'Pair Request',
          theme: theme,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${peer.name} (${peer.host}) wants to pair with this device.',
              style: TextStyle(color: theme.textSecondary),
            ),
            const SizedBox(height: 12),
            PairCodeDisplay(code: widget.request.code, theme: theme),
            const SizedBox(height: 8),
            Text(
              _accepted
                  ? 'Waiting for ${peer.name} to confirm...'
                  : 'Pair only if ${peer.name} shows the same code.',
              style: TextStyle(color: theme.textSecondary, fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: _accepted ? null : _decline,
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: _accepted ? null : _accept,
            child: const Text('Codes Match'),
          ),
        ],
      ),
    );
  }

  Future<void> _decline() async {
    Navigator.of(context).maybePop(IncomingPairDialogResult.declined);
    try {
      await ref
          .read(deviceSyncProvider.notifier)
          .respondToPairRequest(
            requestId: widget.request.requestId,
            accept: false,
          );
    } catch (_) {
      // Request may already be gone (expired or already canceled remotely).
    }
  }

  Future<void> _accept() async {
    setState(() {
      _accepted = true;
      _error = null;
    });
    try {
      await ref
          .read(deviceSyncProvider.notifier)
          .respondToPairRequest(
            requestId: widget.request.requestId,
            accept: true,
          );
      // The event subscription closes the dialog once pairing resolves.
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _accepted = false;
        _error = error.toString();
      });
    }
  }
}
