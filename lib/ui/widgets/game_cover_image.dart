library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Hears when the covers below a [CoverLoadScope] start and finish loading,
/// so a card can hold back its entry reveal until its picture is ready.
abstract interface class CoverLoadListener {
  void coverLoading(Object cover);

  /// The cover has its first frame, failed, or left the tree.
  void coverSettled(Object cover);
}

class CoverLoadScope extends InheritedWidget {
  const CoverLoadScope({
    super.key,
    required this.listener,
    required super.child,
  });

  final CoverLoadListener listener;

  @override
  bool updateShouldNotify(CoverLoadScope oldWidget) =>
      listener != oldWidget.listener;
}

class GameCoverImage extends StatelessWidget {
  const GameCoverImage({
    super.key,
    required this.theme,
    required this.coverImage,
    this.onError,
  });

  final AppThemeData theme;
  final String? coverImage;

  /// Called once if the image fails to load (URL 404, missing file, etc.).
  final VoidCallback? onError;

  static final RegExp _windowsPathPattern = RegExp(r'^[a-zA-Z]:[\\/]');

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 640.0;
      // Reuse decodes across small window size changes. Keep the previous
      // frame visible while a larger decode is loading.
      final pixels = width * MediaQuery.devicePixelRatioOf(context);
      final cacheWidth = ((pixels / 128).ceil() * 128).clamp(128, 2048);
      return _buildImage(cacheWidth);
    },
  );

  Widget _buildImage(int cacheWidth) {
    final raw = coverImage?.trim() ?? '';
    if (raw.isEmpty) return _buildPlaceholder();

    if (raw.startsWith('http')) {
      return CachedNetworkImage(
        key: ValueKey(raw),
        imageUrl: raw,
        useOldImageOnUrlChange: true,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        memCacheWidth: cacheWidth,
        fit: BoxFit.cover,
        // The placeholder shows only while loading: once the image has its
        // first frame (no fade-out) or fails, it leaves the tree.
        placeholder: (context, url) =>
            _CoverLoadReport(loading: true, child: _buildPlaceholder()),
        errorWidget: (context, url, error) => _imageError(),
      );
    }

    if (raw.startsWith('assets/')) {
      return _localImage(AssetImage(raw), raw, cacheWidth);
    }

    final uri = Uri.tryParse(raw);
    final file =
        uri != null && uri.hasScheme && !_windowsPathPattern.hasMatch(raw)
        ? File.fromUri(uri)
        : File(raw);

    return _localImage(FileImage(file), raw, cacheWidth);
  }

  Widget _localImage(ImageProvider provider, String raw, int cacheWidth) =>
      Image(
        image: ResizeImage.resizeIfNeeded(cacheWidth, null, provider),
        key: ValueKey(raw),
        gaplessPlayback: true,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, _) =>
            _CoverLoadReport(loading: frame == null, child: child),
        errorBuilder: (context, error, stackTrace) => _imageError(),
      );

  Widget _imageError() {
    WidgetsBinding.instance.addPostFrameCallback((_) => onError?.call());
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() => Container(
    color: theme.cardCoverPlaceholder,
    child: Center(
      child: Icon(
        Icons.videogame_asset_outlined,
        size: 48,
        color: theme.textHint,
      ),
    ),
  );
}

/// Tells the nearest [CoverLoadScope] whether its cover is still loading.
/// The listener is looked up without a dependency: covers never rebuild for it.
class _CoverLoadReport extends StatefulWidget {
  const _CoverLoadReport({required this.loading, required this.child});

  final bool loading;
  final Widget child;

  @override
  State<_CoverLoadReport> createState() => _CoverLoadReportState();
}

class _CoverLoadReportState extends State<_CoverLoadReport> {
  CoverLoadListener? _listener;

  @override
  void initState() {
    super.initState();
    _listener = context
        .getInheritedWidgetOfExactType<CoverLoadScope>()
        ?.listener;
    if (widget.loading) _listener?.coverLoading(this);
  }

  @override
  void didUpdateWidget(_CoverLoadReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading == oldWidget.loading) return;
    widget.loading
        ? _listener?.coverLoading(this)
        : _listener?.coverSettled(this);
  }

  @override
  void dispose() {
    if (widget.loading) _listener?.coverSettled(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
