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
/// Closes automatically when the pairing session is resolved — trusted,
/// canceled, or timed out — via the service event stream.  MITM protection
/// is preserved: the entered code is encrypted with a key derived from an
/// x25519 DH exchange between the two devices' static key-pairs (HKDF +
/// AES-GCM), so a network-level attacker cannot intercept or forge it.
class IncomingPairDialog extends ConsumerStatefulWidget {
  const IncomingPairDialog({super.key, required this.request});
  final PendingPairRequest request;

  @override
  ConsumerState<IncomingPairDialog> createState() => _IncomingPairDialogState();
}

class _IncomingPairDialogState extends ConsumerState<IncomingPairDialog> {
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  bool _submitting = false;
  String? _error;
  StreamSubscription<SyncEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    // Request focus after the first frame so DialogInteractionScope's
    // autofocus has settled and the PairCodeInput TextField gets it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    _eventSub = ref.read(deviceSyncServiceProvider).syncEvents.listen((event) {
      if (!mounted) return;

      if (event is PairRequestCodeRejectedEvent &&
          event.request.requestId == widget.request.requestId) {
        _codeController.clear();
        _focusNode.requestFocus();
        setState(() {
          _submitting = false;
          _error = 'Incorrect code. Please try again.';
        });
        return;
      }

      final shouldClose = switch (event) {
        PairRequestCanceledEvent e
            when e.request.requestId == widget.request.requestId =>
          true,
        PairRequestTimedOutEvent e
            when e.request.requestId == widget.request.requestId =>
          true,
        PeerTrustedEvent e when e.peer.id == widget.request.peer.id => true,
        _ => false,
      };

      if (shouldClose) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).maybePop(IncomingPairDialogResult.resolved);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return DialogInteractionScope(
      onPrimaryAction: _submitting ? null : _sendCode,
      onDismiss: _submitting ? null : _decline,
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
              'Allow ${widget.request.peer.name} (${widget.request.peer.host})'
              ' to pair with this device?',
              style: TextStyle(color: theme.textSecondary),
            ),
            const SizedBox(height: 12),
            PairCodeInput(
              controller: _codeController,
              focusNode: _focusNode,
              theme: theme,
              error: _error,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) {
                if (!_submitting) _sendCode();
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the 6-digit code shown on the sending device.',
              style: TextStyle(color: theme.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: _submitting ? null : _decline,
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: _submitting ? null : _sendCode,
            child: const Text('Send Code'),
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

  Future<void> _sendCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the 6-digit pairing code.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(deviceSyncProvider.notifier)
          .respondToPairRequest(
            requestId: widget.request.requestId,
            accept: true,
            enteredVerificationCode: code,
          );
      // Stay in submitting state — the event subscription above will close
      // the dialog on PeerTrustedEvent (success) or close/error on
      // PairRequestCanceled/TimedOut.  Code rejections reset _submitting.
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString().replaceFirst('DeviceSyncException: ', '');
      });
    }
  }
}
