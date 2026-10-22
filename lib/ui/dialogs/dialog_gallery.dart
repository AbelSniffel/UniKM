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

/// Real dialogs on a canvas, with isolated data and visible previews cached.
class DialogGallery extends ConsumerStatefulWidget {
  const DialogGallery({super.key});

  @override
  ConsumerState<DialogGallery> createState() => _DialogGalleryState();
}

class _DialogGalleryState extends ConsumerState<DialogGallery> {
  static const _cell = Size(700, 800);
  static const _minScale = 0.2;
  final _transform = TransformationController();
  bool _constraining = false;
  int _columns = 8;
  bool _columnsInitialized = false;
  bool _fit = true;
  Size _viewport = Size.zero;
  int _count = 0;

  Size get _canvas =>
      Size(_columns * _cell.width, (_count / _columns).ceil() * _cell.height);

  @override
  void initState() {
    super.initState();
    _transform.addListener(_constrainTransform);
  }

  void _constrainTransform() {
    if (_constraining || _viewport.isEmpty || _canvas.isEmpty) return;
    final matrix = _transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    double constrainAxis(
      double offset,
      double viewport,
      double content,
      double cellExtent,
    ) {
      // Allow the first and last preview centers to reach the viewport center.
      // Also keep the edges reachable when a preview exceeds the viewport.
      final minOffset = math.min(
        viewport - content - 24,
        viewport / 2 - content + cellExtent / 2,
      );
      final maxOffset = math.max(24.0, viewport / 2 - cellExtent / 2);
      return offset.clamp(minOffset, maxOffset);
    }

    final x = constrainAxis(
      translation.x,
      _viewport.width,
      _canvas.width * scale,
      _cell.width * scale,
    );
    final y = constrainAxis(
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

  void _fitAll() {
    if (_viewport.isEmpty || _count == 0) return;
    final scale = math
        .min(
          (_viewport.width - 24) / _canvas.width,
          (_viewport.height - 24) / _canvas.height,
        )
        .clamp(_minScale, 1.0);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (_viewport.width - _canvas.width * scale) / 2,
        (_viewport.height - _canvas.height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _zoom(double scale) {
    _fit = false;
    final nextScale = scale.clamp(_minScale, 2.0);
    final center = _viewport.center(Offset.zero);
    final point = _transform.toScene(center);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        center.dx - point.dx * nextScale,
        center.dy - point.dy * nextScale,
        0,
        1,
      )
      ..scaleByDouble(nextScale, nextScale, nextScale, 1);
  }

  void _changeColumns(int change) {
    setState(() => _columns = (_columns + change).clamp(2, 12));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fit ? _fitAll() : _constrainTransform();
    });
  }

  @override
  void dispose() {
    _transform.removeListener(_constrainTransform);
    _transform.dispose();
    super.dispose();
  }

  Widget _instructions(AppThemeData theme) => Text(
    'Drag to pan • scroll to zoom • live previews',
    key: const ValueKey('dialog-gallery-instructions'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: TextStyle(color: theme.textSecondary),
  );

  Widget _header(AppThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.min(
                          260,
                          math.max(0, constraints.maxWidth - 104),
                        ),
                      ),
                      child: Container(
                        key: const ValueKey('dialog-gallery-title'),
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
                  if (wide)
                    Center(
                      child: SizedBox(
                        width: constraints.maxWidth - 560,
                        child: _instructions(theme),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                  ),
                ],
              ),
            ),
            if (!wide)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Center(child: _instructions(theme)),
              ),
          ],
        );
      },
    ),
  );

  Widget _zoomControls(AppThemeData theme) => Row(
    key: const ValueKey('dialog-gallery-zoom-controls'),
    mainAxisSize: MainAxisSize.min,
    spacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: () {
          _fit = true;
          _fitAll();
        },
        icon: const Icon(Icons.fit_screen),
        label: const Text('Fit all'),
      ),
      OutlinedButton(onPressed: () => _zoom(1), child: const Text('100%')),
      IconButton(
        tooltip: 'Zoom out',
        onPressed: () => _zoom(_transform.value.getMaxScaleOnAxis() / 1.25),
        icon: const Icon(Icons.remove),
      ),
      ValueListenableBuilder<Matrix4>(
        valueListenable: _transform,
        builder: (_, matrix, _) => Text(
          '${(matrix.getMaxScaleOnAxis() * 100).round()}%',
          style: TextStyle(color: theme.textSecondary),
        ),
      ),
      IconButton(
        tooltip: 'Zoom in',
        onPressed: () => _zoom(_transform.value.getMaxScaleOnAxis() * 1.25),
        icon: const Icon(Icons.add),
      ),
    ],
  );

  Widget _layoutControls(AppThemeData theme) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 8,
    children: [
      IconButton(
        tooltip: 'Fewer columns',
        onPressed: _columns > 2 ? () => _changeColumns(-1) : null,
        icon: const Icon(Icons.remove),
      ),
      Text('$_columns columns', style: TextStyle(color: theme.textSecondary)),
      IconButton(
        tooltip: 'More columns',
        onPressed: _columns < 12 ? () => _changeColumns(1) : null,
        icon: const Icon(Icons.add),
      ),
    ],
  );

  Widget _footer(AppThemeData theme) => Padding(
    padding: const EdgeInsets.all(8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final zoom = _zoomControls(theme);
        final layout = _layoutControls(theme);
        if (constraints.maxWidth >= 1000) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [zoom, layout],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [zoom, const SizedBox(width: 24), layout],
          ),
        );
      },
    ),
  );

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
    final entries = buildDialogGalleryCatalog();
    // Reuse widget instances while the viewer transforms. Panning should only
    // reposition cached layers, without rebuilding each dialog's controls.
    final previews = [
      for (final entry in entries)
        RepaintBoundary(
          child: _DialogGalleryTile(
            key: ValueKey((entry.id, theme, cardStyle)),
            entry: entry,
            theme: theme,
            appearanceSettings: appearanceSettings,
          ),
        ),
    ];
    _count = entries.length;
    if (!_columnsInitialized) {
      final window = MediaQuery.sizeOf(context);
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
      _columnsInitialized = true;
    }
    return Theme(
      data: ref.watch(themeDataProvider),
      child: Scaffold(
        backgroundColor: theme.background,
        body: SafeArea(
          child: Column(
            children: [
              PageBarSurface(theme: theme, child: _header(theme)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewport = constraints.biggest;
                    if (_viewport != viewport) {
                      _viewport = viewport;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _fit ? _fitAll() : _constrainTransform();
                      });
                    }
                    return ClipRect(
                      child: InteractiveViewer.builder(
                        transformationController: _transform,
                        alignment: Alignment.topLeft,
                        // Enforce screen-space bounds ourselves. Flutter's
                        // scene-space boundary correction can jump on scaling.
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        minScale: _minScale,
                        maxScale: 2,
                        onInteractionStart: (_) => _fit = false,
                        builder: (context, viewport) {
                          final points = [
                            viewport.point0,
                            viewport.point1,
                            viewport.point2,
                            viewport.point3,
                          ];
                          final visible = Rect.fromLTRB(
                            points.map((p) => p.x).reduce(math.min),
                            points.map((p) => p.y).reduce(math.min),
                            points.map((p) => p.x).reduce(math.max),
                            points.map((p) => p.y).reduce(math.max),
                          ).inflate(100);
                          return SizedBox(
                            width: _canvas.width,
                            height: _canvas.height,
                            child: Stack(
                              children: [
                                for (final (index, entry) in entries.indexed)
                                  if (_cellRect(index).overlaps(visible))
                                    Positioned.fromRect(
                                      key: ValueKey(entry.id),
                                      rect: _cellRect(index).deflate(8),
                                      child: previews[index],
                                    ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              PageBarSurface(
                theme: theme,
                isFooter: true,
                child: _footer(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Rect _cellRect(int index) => Rect.fromLTWH(
    (index % _columns) * _cell.width,
    (index ~/ _columns) * _cell.height,
    _cell.width,
    _cell.height,
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
  late final ProviderContainer _container;
  final _dismissals = <VoidCallback>[];
  final _contentRevision = ValueNotifier<int>(0);
  WidgetBuilder? _builder;
  String? _error;
  bool _scheduled = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _container = createDialogGalleryContainer(
      widget.theme,
      appearanceSettings: widget.appearanceSettings,
    );
  }

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
  Widget build(BuildContext context) => SectionGroupBox(
    theme: widget.theme,
    title: widget.entry.label,
    titleLocation: SectionTitleLocation.top,
    headerBottomPadding: 8,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(widget.theme.cornerRadius),
      child: ColoredBox(color: widget.theme.surface, child: _preview(context)),
    ),
  );

  Widget _preview(BuildContext context) => FittedBox(
    fit: BoxFit.contain,
    child: SizedBox.fromSize(
      size: widget.entry.viewport,
      child: UncontrolledProviderScope(
        container: _container,
        child: Consumer(
          builder: (context, ref, _) {
            final theme = ref.watch(themeProvider);
            return Theme(
              data: theme.toThemeData(),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: widget.entry.viewport,
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
                      // Keep close callbacks and automatic dismissals inside
                      // this preview instead of reaching the main program.
                      child: Navigator(
                        onGenerateRoute: (_) => PageRouteBuilder<void>(
                          transitionDuration: Duration.zero,
                          pageBuilder: (context, _, _) =>
                              ValueListenableBuilder<int>(
                                valueListenable: _contentRevision,
                                builder: (context, _, _) {
                                  _scheduleOpen(context);
                                  return _error != null
                                      ? Center(
                                          child: Text(
                                            'Preview failed: $_error',
                                            style: TextStyle(
                                              color: theme.error,
                                            ),
                                          ),
                                        )
                                      : _builder == null
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
            );
          },
        ),
      ),
    ),
  );
}
