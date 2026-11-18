library;

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

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

class GameCoverImage extends StatefulWidget {
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

  @override
  State<GameCoverImage> createState() => _GameCoverImageState();

  static final RegExp _windowsPathPattern = RegExp(r'^[a-zA-Z]:[\\/]');

  /// The decode width for a cover [width] logical pixels wide: device pixels
  /// rounded up to steps of 128, so small size changes reuse a decode.
  static int decodeWidth(double width, double pixelRatio) =>
      ((width * pixelRatio / 128).ceil() * 128).clamp(128, 2048);

  /// The provider of the local cover at [raw], an asset or a file, decoded
  /// [cacheWidth] pixels wide.
  static ImageProvider localProvider(String raw, int cacheWidth) {
    if (raw.startsWith('assets/')) {
      return ResizeImage.resizeIfNeeded(cacheWidth, null, AssetImage(raw));
    }
    final uri = Uri.tryParse(raw);
    final file =
        uri != null && uri.hasScheme && !_windowsPathPattern.hasMatch(raw)
        ? File.fromUri(uri)
        : File(raw);
    return ResizeImage.resizeIfNeeded(cacheWidth, null, FileImage(file));
  }
}

class _GameCoverImageState extends State<GameCoverImage> {
  /// The image built last and what it depends on: a resize that keeps the
  /// decode size returns the same widget, so its subtree is not rebuilt.
  Widget? _image;
  Object? _imageKey;

  /// The decode width in use. While the size changes, as when the window
  /// resizes, it is held, so covers do not decode again at every step, and
  /// the new one is taken once the size settles. Never more than one step
  /// too small.
  int? _cacheWidth;
  Timer? _settle;

  AppThemeData get theme => widget.theme;

  int _heldCacheWidth(int needed) {
    _settle?.cancel();
    final held = _cacheWidth;
    if (held == null || needed == held || needed > held + 128) {
      return _cacheWidth = needed;
    }
    _settle = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _cacheWidth = null);
    });
    return held;
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 640.0;
      // Reuse decodes across small window size changes. Keep the previous
      // frame visible while a larger decode is loading.
      final cacheWidth = _heldCacheWidth(
        GameCoverImage.decodeWidth(
          width,
          MediaQuery.devicePixelRatioOf(context),
        ),
      );
      final key = (
        cacheWidth,
        widget.coverImage,
        widget.theme,
        widget.onError == null,
      );
      if (key != _imageKey) {
        _imageKey = key;
        _image = _buildImage(cacheWidth);
      }
      return _image!;
    },
  );

  Widget _buildImage(int cacheWidth) {
    final raw = widget.coverImage?.trim() ?? '';
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

    return _localImage(GameCoverImage.localProvider(raw, cacheWidth), raw);
  }

  Widget _localImage(ImageProvider provider, String raw) => Image(
    image: provider,
    key: ValueKey(raw),
    gaplessPlayback: true,
    fit: BoxFit.cover,
    // The loading tone shows under the picture until its first frame; a
    // picture kept while a larger one loads stays on top of it.
    frameBuilder: (context, child, frame, _) => _CoverLoadReport(
      loading: frame == null,
      child: frame == null
          ? Stack(
              fit: StackFit.passthrough,
              alignment: Alignment.center,
              children: [_buildPlaceholder(), child],
            )
          : child,
    ),
    errorBuilder: (context, error, stackTrace) => _imageError(),
  );

  Widget _imageError() {
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onError?.call());
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
