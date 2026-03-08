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
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.videogame_asset_outlined,
  });

  final AppThemeData theme;
  final String? coverImage;
  final BoxFit fit;
  final IconData placeholderIcon;

  static final RegExp _windowsPathPattern = RegExp(r'^[a-zA-Z]:[\\/]');

  @override
  Widget build(BuildContext context) {
    final raw = coverImage?.trim() ?? '';
    if (raw.isEmpty) return _buildPlaceholder();

    if (raw.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: raw,
        fit: fit,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }

    if (raw.startsWith('assets/')) {
      return Image.asset(
        raw,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    final uri = Uri.tryParse(raw);
    final file = uri != null && uri.hasScheme && !_windowsPathPattern.hasMatch(raw)
        ? File.fromUri(uri)
        : File(raw);

    return Image.file(
      file,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: theme.cardCoverPlaceholder,
      child: Center(
        child: Icon(
          placeholderIcon,
          size: 52,
          color: theme.textHint,
        ),
      ),
    );
  }
}
