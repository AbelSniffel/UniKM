library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

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
        placeholder: (context, url) => _buildPlaceholder(),
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

  Widget _localImage(ImageProvider provider, String raw, int cacheWidth) {
    return Image(
      image: ResizeImage.resizeIfNeeded(cacheWidth, null, provider),
      key: ValueKey(raw),
      gaplessPlayback: true,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _imageError(),
    );
  }

  Widget _imageError() {
    WidgetsBinding.instance.addPostFrameCallback((_) => onError?.call());
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: theme.cardCoverPlaceholder,
      child: Center(
        child: Icon(
          Icons.videogame_asset_outlined,
          size: 52,
          color: theme.textHint,
        ),
      ),
    );
  }
}
