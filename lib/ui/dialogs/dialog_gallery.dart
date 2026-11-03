import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_model.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/navigation_theme_menu.dart';
import '../widgets/page_bar_surface.dart';
import '../widgets/section_groupbox.dart';
import 'dialog_gallery_catalog.dart';

void showDialogGallery(BuildContext context) => ProviderScope.containerOf(
  context,
  listen: false,
).read(dialogGalleryVisibleProvider.notifier).set(true);

/// Keeps normal pages mounted while opening a temporary page below the title bar.
class DialogGalleryHost extends ConsumerWidget {
  const DialogGalleryHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(dialogGalleryVisibleProvider);
    void close() => ref.read(dialogGalleryVisibleProvider.notifier).set(false);

    return PopScope(
      canPop: !visible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && visible) close();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: visible,
            child: ExcludeFocus(
              excluding: visible,
              child: TickerMode(enabled: !visible, child: child),
            ),
          ),
          if (visible)
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): close,
              },
              child: const FocusScope(autofocus: true, child: DialogGallery()),
            ),
        ],
      ),
    );
  }
}

/// Real dialogs on a canvas, with isolated data. Every preview stays built,
/// so panning and zooming only move the canvas.
class DialogGallery extends ConsumerStatefulWidget {
  const DialogGallery({super.key});

  @override
  ConsumerState<DialogGallery> createState() => _DialogGalleryState();
}

class _DialogGalleryState extends ConsumerState<DialogGallery> {
  static const _cell = Size(700, 800);
  static const _maxScale = 2.0;
  final _transform = TransformationController();
  bool _constraining = false;
  int? _columns;
  bool _fit = true;
  Size _viewport = Size.zero;
  int _count = 0;

  int get _rows => (_count / _columns!).ceil();
  Size get _canvas => Size(_columns! * _cell.width, _rows * _cell.height);
  double get _scale => _transform.value.getMaxScaleOnAxis();

  /// The scale that shows every preview; zooming out stops at 20%, or here
  /// when the window is too small for that.
  double get _fitScale => math
      .min(
        (_viewport.width - 24) / _canvas.width,
        (_viewport.height - 24) / _canvas.height,
      )
      .clamp(0.01, 1.0);
  double get _minScale => math.min(0.2, _fitScale);

  @override
  void initState() {
    super.initState();
    _transform.addListener(_constrainTransform);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Lets the first and last preview centres reach the viewport centre, and
  /// keeps the edges reachable when a preview is larger than the viewport.
  void _constrainTransform() {
    if (_constraining || _viewport.isEmpty || _count == 0) return;
    final matrix = _transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    double clamp(double offset, double viewport, double content, double cell) {
      final min = math.min(
        viewport - content - 24,
        viewport / 2 - content + cell / 2,
      );
      return offset.clamp(min, math.max(24.0, viewport / 2 - cell / 2));
    }

    final x = clamp(
      translation.x,
      _viewport.width,
      _canvas.width * scale,
      _cell.width * scale,
    );
    final y = clamp(
      translation.y,
      _viewport.height,
      _canvas.height * scale,
      _cell.height * scale,
    );
    if ((x - translation.x).abs() < 0.001 &&
        (y - translation.y).abs() < 0.001) {
      return;
    }
    _constraining = true;
    _transform.value = matrix.clone()..setTranslationRaw(x, y, translation.z);
    _constraining = false;
  }

  /// Scales about the viewport centre, or fits the whole canvas when [scale]
  /// is null.
  void _setScale(double? scale) {
    if (_viewport.isEmpty || _count == 0) return;
    _fit = scale == null;
    final next = scale?.clamp(_minScale, _maxScale) ?? _fitScale;
    final center = _viewport.center(Offset.zero);
    final point = _fit
        ? _canvas.center(Offset.zero)
        : _transform.toScene(center);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        center.dx - point.dx * next,
        center.dy - point.dy * next,
        0,
        1,
      )
      ..scaleByDouble(next, next, next, 1);
  }

  /// Re-fits, or keeps the canvas in bounds, once the new layout is in.
  void _refit() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _fit ? _setScale(null) : _constrainTransform();
  });

  void _changeColumns(int change) {
    setState(() => _columns = (_columns! + change).clamp(2, 12));
    _refit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final cardStyle = (
      ref.watch(settingsCardIndicatorStyleProvider),
      ref.watch(toggleStyleProvider),
    );
    final appearanceSettings = <String, dynamic>{
      SettingsKeys.settingsCardIndicatorStyle: cardStyle.$1,
      SettingsKeys.toggleStyle: cardStyle.$2,
    };
    // Rebuilt with each build, so hot reload refreshes inline builders.
    final entries = buildDialogGalleryCatalog();
    _count = entries.length;
    // From the window's shape. [View] does not notify on resize, so resizing
    // never rebuilds the gallery.
    if (_columns == null) {
      final view = View.of(context);
      final window = view.physicalSize / view.devicePixelRatio;
      _columns = math
          .sqrt(
            _count *
                window.width /
                math.max(1, window.height - 128) *
                _cell.height /
                _cell.width,
          )
          .ceil()
          .clamp(2, 12);
    }
    // Built here rather than in the viewport's LayoutBuilder, so a resize
    // reuses these widgets and leaves every preview as it is.
    final canvas = SizedBox(
      width: _canvas.width,
      child: Wrap(
        children: [
          for (final entry in entries)
            Container(
              key: ValueKey(entry.id),
              width: _cell.width,
              height: _cell.height,
              padding: const EdgeInsets.all(8),
              // Its own layer, which panning only moves.
              child: RepaintBoundary(
                child: _DialogGalleryTile(
                  key: ValueKey((entry.id, theme, cardStyle)),
                  entry: entry,
                  theme: theme,
                  appearanceSettings: appearanceSettings,
                ),
              ),
            ),
        ],
      ),
    );
    final secondary = TextStyle(color: theme.textSecondary);
    return Theme(
      data: ref.watch(themeDataProvider),
      child: Scaffold(
        backgroundColor: theme.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageBarSurface(theme: theme, child: _header(theme)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (_viewport != constraints.biggest) {
                      _viewport = constraints.biggest;
                      _refit();
                    }
                    return ClipRect(
                      child: InteractiveViewer(
                        transformationController: _transform,
                        constrained: false,
                        alignment: Alignment.topLeft,
                        // Bounds are kept in screen space by
                        // [_constrainTransform]; Flutter's scene-space
                        // correction jumps while scaling.
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        minScale: _minScale,
                        maxScale: _maxScale,
                        onInteractionStart: (_) => _fit = false,
                        child: canvas,
                      ),
                    );
                  },
                ),
              ),
              PageBarSurface(
                theme: theme,
                isFooter: true,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  // One row when it fits; zoom above layout when narrow.
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 24,
                    runSpacing: 4,
                    children: [
                      Row(
                        key: const ValueKey('dialog-gallery-zoom-controls'),
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _setScale(null),
                            icon: const Icon(Icons.fit_screen),
                            label: const Text('Fit all'),
                          ),
                          OutlinedButton(
                            onPressed: () => _setScale(1),
                            child: const Text('100%'),
                          ),
                          IconButton(
                            tooltip: 'Zoom out',
                            onPressed: () => _setScale(_scale / 1.25),
                            icon: const Icon(Icons.remove),
                          ),
                          ValueListenableBuilder<Matrix4>(
                            valueListenable: _transform,
                            builder: (_, matrix, _) => Text(
                              '${(matrix.getMaxScaleOnAxis() * 100).round()}%',
                              style: secondary,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Zoom in',
                            onPressed: () => _setScale(_scale * 1.25),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          IconButton(
                            tooltip: 'Fewer columns',
                            onPressed: _columns! > 2
                                ? () => _changeColumns(-1)
                                : null,
                            icon: const Icon(Icons.remove),
                          ),
                          Text('$_columns columns', style: secondary),
                          IconButton(
                            tooltip: 'More columns',
                            onPressed: _columns! < 12
                                ? () => _changeColumns(1)
                                : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The title on the left and the theme and close buttons on the right,
  /// with the hint centred between them, or below them when narrow.
  Widget _header(AppThemeData theme) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 920;
      final hint = Text(
        'Drag to pan • scroll to zoom • live previews',
        key: const ValueKey('dialog-gallery-instructions'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(color: theme.textSecondary),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (wide)
                    SizedBox(width: constraints.maxWidth - 576, child: hint),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            key: const ValueKey('dialog-gallery-title'),
                            constraints: const BoxConstraints(maxWidth: 260),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(
                                theme.cornerRadius,
                              ),
                            ),
                            child: Text(
                              'Dialog Gallery ($_count)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      NavigationThemeMenuButton(
                        theme: theme,
                        position: NavBarPosition.top,
                      ),
                      IconButton(
                        tooltip: 'Close gallery',
                        onPressed: () => ref
                            .read(dialogGalleryVisibleProvider.notifier)
                            .set(false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!wide) hint,
          ],
        ),
      );
    },
  );
}

class _DialogGalleryTile extends StatefulWidget {
  const _DialogGalleryTile({
    super.key,
    required this.entry,
    required this.theme,
    required this.appearanceSettings,
  });
  final DialogGalleryEntry entry;
  final AppThemeData theme;
  final Map<String, dynamic> appearanceSettings;
  @override
  State<_DialogGalleryTile> createState() => _DialogGalleryTileState();
}

class _DialogGalleryTileState extends State<_DialogGalleryTile> {
  late final _container = createDialogGalleryContainer(
    widget.theme,
    appearanceSettings: widget.appearanceSettings,
  );
  final _dismissals = <VoidCallback>[];
  final _contentRevision = ValueNotifier<int>(0);
  WidgetBuilder? _builder;
  String? _error;
  bool _scheduled = false;
  int _generation = 0;

  Future<T?> _capture<T>(WidgetBuilder builder) {
    final result = Completer<T?>();
    _dismissals.add(() {
      if (!result.isCompleted) result.complete(null);
    });
    if (mounted) {
      _builder = builder;
      _contentRevision.value++;
    }
    return result.future;
  }

  void _scheduleOpen(BuildContext previewContext) {
    if (_scheduled) return;
    _scheduled = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      Future<Object?>.sync(() => widget.entry.open(previewContext)).catchError((
        Object error,
        StackTrace stack,
      ) {
        if (mounted && generation == _generation) {
          _error = error.toString();
          _contentRevision.value++;
        }
        return null;
      });
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    // Re-run inline builders as well as normal Widget.build methods after reload.
    _generation++;
    _scheduled = false;
    _builder = null;
    _error = null;
    _dismiss();
    _contentRevision.value++;
  }

  void _dismiss() {
    for (final dismiss in _dismissals) {
      dismiss();
    }
    _dismissals.clear();
  }

  @override
  void dispose() {
    _dismiss();
    _contentRevision.dispose();
    // Descendant dialogs may cancel theme previews in dispose. Their container
    // must remain alive until the subtree has finished unmounting.
    WidgetsBinding.instance.addPostFrameCallback((_) => _container.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final viewport = widget.entry.viewport;
    return SectionGroupBox(
      theme: theme,
      title: widget.entry.label,
      titleLocation: SectionTitleLocation.top,
      headerBottomPadding: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        child: ColoredBox(
          color: theme.surface,
          child: FittedBox(
            child: SizedBox.fromSize(
              size: viewport,
              child: UncontrolledProviderScope(
                container: _container,
                child: Consumer(
                  // The cached ThemeData, and the view rather than the
                  // inherited MediaQuery (whose size changes with every
                  // resize), so nothing above the dialog's own Navigator
                  // changes unless the theme does.
                  builder: (context, ref, _) => Theme(
                    data: ref.watch(themeDataProvider),
                    child: MediaQuery(
                      data: MediaQueryData.fromView(View.of(context)).copyWith(
                        size: viewport,
                        padding: EdgeInsets.zero,
                        viewPadding: EdgeInsets.zero,
                        viewInsets: EdgeInsets.zero,
                      ),
                      child: ExcludeFocus(
                        child: AbsorbPointer(
                          child: AppDialogPreviewScope(
                            present: _capture,
                            databaseFiles: galleryDatabaseFiles,
                            steamCachedAt: galleryDate,
                            steamResult: widget.entry.cachedSteam
                                ? gallerySteamResult
                                : null,
                            // Keep close callbacks and automatic dismissals
                            // inside this preview instead of reaching the
                            // main program.
                            child: Navigator(
                              onGenerateRoute: (_) => PageRouteBuilder<void>(
                                transitionDuration: Duration.zero,
                                pageBuilder: (context, _, _) =>
                                    ValueListenableBuilder<int>(
                                      valueListenable: _contentRevision,
                                      builder: (context, _, _) {
                                        _scheduleOpen(context);
                                        if (_error != null) {
                                          return Center(
                                            child: Text(
                                              'Preview failed: $_error',
                                              style: TextStyle(
                                                color: theme.error,
                                              ),
                                            ),
                                          );
                                        }
                                        return _builder == null
                                            ? const SizedBox.shrink()
                                            : Builder(builder: _builder!);
                                      },
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
