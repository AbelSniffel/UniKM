/// Main application scaffold - root widget with navigation
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/constants/app_constants.dart';
import '../core/services/backup_service.dart';
import '../core/services/logging.dart';
import '../core/services/update_service.dart';
import '../core/settings/settings_model.dart';
import '../core/theme/app_theme.dart';
import '../providers/app_providers.dart';
import 'dialogs/import_export_dialog.dart';
import 'pages/add_games_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/update_page.dart';
import 'widgets/navigation_panel.dart' as nav_panel;
import 'widgets/animated_gradient_bar.dart';
import 'widgets/dev_window.dart';
import 'widgets/notification_system.dart';

const bool _kDisablePersistentPages =
    false; // Set to true to rebuild pages on each navigation (disables persistent pages)

/// Navigation items
/// Main app scaffold
class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> with WindowListener {
  Timer? _windowSaveDebounce;
  bool _applyingSavedWindowState = false;
  Timer? _autoBackupTimer;
  Timer? _autoUpdateTimer;
  bool _isClosingWindow = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initWindow();
    _initAutoBackup();
    _initAutoUpdateChecks();
  }

  @override
  void dispose() {
    _windowSaveDebounce?.cancel();
    _autoBackupTimer?.cancel();
    _autoUpdateTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  void _initAutoBackup() {
    // Start auto backup after a short delay to ensure settings are loaded
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _updateAutoBackup();
    });
  }

  void _initAutoUpdateChecks() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleNextAutoUpdateCheck(useStartupDelay: true);
    });
  }

  void _updateAutoBackup() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;

    final shellSettings = ref.read(appShellSettingsProvider);
    final autoBackupEnabled = shellSettings.autoBackupEnabled;
    final intervalMinutes = shellSettings.autoBackupIntervalMinutes;

    if (autoBackupEnabled && intervalMinutes > 0) {
      final interval = Duration(minutes: intervalMinutes);

      // Update the next backup time provider
      ref
          .read(nextAutoBackupTimeProvider.notifier)
          .setNextBackupTime(DateTime.now().add(interval));

      _autoBackupTimer = Timer.periodic(interval, (_) async {
        if (!mounted) return;

        // Update next backup time
        ref
            .read(nextAutoBackupTimeProvider.notifier)
            .setNextBackupTime(DateTime.now().add(interval));

        try {
          final backupService = ref.read(backupServiceProvider);
          final result = await backupService.createBackup();
          if (result.success) {
            // Silent success - don't spam notifications for auto backups
            // Only log in debug mode
            if (ref.read(appShellSettingsProvider).developerMode) {
              NotificationManager.instance.info(
                'Auto backup created: ${result.backupInfo?.fileName}',
              );
            }
          }
        } catch (e) {
          // Silent failure for auto backups - log but don't disrupt user
          AppLog.w('Auto backup failed', error: e);
        }
      });
    } else {
      // Clear next backup time if disabled
      ref.read(nextAutoBackupTimeProvider.notifier).setNextBackupTime(null);
    }
  }

  void _scheduleNextAutoUpdateCheck({bool useStartupDelay = false}) {
    _autoUpdateTimer?.cancel();
    _autoUpdateTimer = null;

    final updatesSettings = ref.read(updatesSettingsProvider);
    if (!updatesSettings.autoCheckEnabled ||
        updatesSettings.autoCheckIntervalMinutes <= 0) {
      ref.read(nextAutoUpdateTimeProvider.notifier).setNextUpdateTime(null);
      return;
    }

    final delay = useStartupDelay
        ? const Duration(seconds: 3)
        : Duration(minutes: updatesSettings.autoCheckIntervalMinutes);

    ref
        .read(nextAutoUpdateTimeProvider.notifier)
        .setNextUpdateTime(DateTime.now().add(delay));

    _autoUpdateTimer = Timer(delay, () async {
      if (!mounted) return;

      try {
        final updateState = ref.read(updateProvider);
        if (!updateState.isChecking) {
          await ref.read(updateProvider.notifier).checkForUpdates();
        }
      } catch (e) {
        AppLog.w('Automatic update check failed', error: e);
      }

      if (!mounted) return;
      _scheduleNextAutoUpdateCheck();
    });
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    // Prevent immediate close so we can persist encrypted DB changes.
    await windowManager.setPreventClose(true);

    _applyingSavedWindowState = true;
    final shellSettings = ref.read(appShellSettingsProvider);
    final initialSize = await _resolveInitialWindowSize(shellSettings);

    final windowOptions = WindowOptions(
      size: initialSize,
      minimumSize: const Size(kMinWindowWidth, kMinWindowHeight),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: AppConstants.appTitle,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await _positionWindowOnPrimaryDisplay(initialSize);
      if (shellSettings.windowMaximized) {
        await windowManager.maximize();
      }
      await _requestInitialWindowFocus();

      _applyingSavedWindowState = false;
    });
  }

  Future<void> _requestInitialWindowFocus() async {
    await windowManager.show();
    await windowManager.focus();

    if (Platform.isWindows) {
      try {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.focus();
      } catch (_) {
        // Best effort only.
      }

      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 160), () async {
          if (!mounted) return;
          try {
            await windowManager.setAlwaysOnTop(false);
            await windowManager.focus();
          } catch (_) {
            // Best effort only.
          }
        }),
      );
      return;
    }

    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 80), () async {
        if (!mounted) return;
        try {
          await windowManager.focus();
        } catch (_) {
          // Best effort only.
        }
      }),
    );
  }

  Future<Size> _resolveInitialWindowSize(AppShellSettings shellSettings) async {
    final primaryDisplay = await screenRetriever.getPrimaryDisplay();
    final visibleSize = primaryDisplay.visibleSize ?? primaryDisplay.size;
    final maxWidth = visibleSize.width.toDouble();
    final maxHeight = visibleSize.height.toDouble();
    final minWidth = math.min(kMinWindowWidth, maxWidth);
    final minHeight = math.min(kMinWindowHeight, maxHeight);
    final hasSavedPlacement =
        shellSettings.windowX != null && shellSettings.windowY != null;

    final preferredWidth = hasSavedPlacement
        ? shellSettings.windowWidth
        : kDefaultWindowWidth;
    final preferredHeight = hasSavedPlacement
        ? shellSettings.windowHeight
        : kDefaultWindowHeight;

    return Size(
      preferredWidth.clamp(minWidth, maxWidth),
      preferredHeight.clamp(minHeight, maxHeight),
    );
  }

  Future<void> _positionWindowOnPrimaryDisplay(Size windowSize) async {
    final primaryDisplay = await screenRetriever.getPrimaryDisplay();
    final visibleSize = primaryDisplay.visibleSize ?? primaryDisplay.size;
    final visiblePosition =
        primaryDisplay.visiblePosition ?? const Offset(0, 0);
    final centeredX =
        visiblePosition.dx + ((visibleSize.width - windowSize.width) / 2);
    final centeredY =
        visiblePosition.dy + ((visibleSize.height - windowSize.height) / 2);

    await windowManager.setPosition(Offset(centeredX, centeredY));
  }

  void _scheduleSaveWindowState() {
    if (_applyingSavedWindowState) return;

    _windowSaveDebounce?.cancel();
    _windowSaveDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final size = await windowManager.getSize();
        final pos = await windowManager.getPosition();
        final maximized = await windowManager.isMaximized();

        final settingsNotifier = ref.read(settingsProvider.notifier);
        await settingsNotifier.setSetting(SettingsKeys.windowWidth, size.width);
        await settingsNotifier.setSetting(
          SettingsKeys.windowHeight,
          size.height,
        );
        await settingsNotifier.setSetting(SettingsKeys.windowX, pos.dx);
        await settingsNotifier.setSetting(SettingsKeys.windowY, pos.dy);
        await settingsNotifier.setSetting(
          SettingsKeys.windowMaximized,
          maximized,
        );
      } catch (_) {
        // Best effort only
      }
    });
  }

  @override
  void onWindowResized() => _scheduleSaveWindowState();

  @override
  void onWindowMoved() => _scheduleSaveWindowState();

  @override
  void onWindowMaximize() => _scheduleSaveWindowState();

  @override
  void onWindowUnmaximize() => _scheduleSaveWindowState();

  Future<void> _cleanupOnClose() async {
    final session = ref.read(encryptedDbSessionProvider);
    if (session != null) {
      try {
        if (session.shouldPersistOnClose()) {
          NotificationManager.instance.info('Saving encrypted database…');
        }
        await session.closeAndPersist(ref.read(requireDatabaseProvider));
      } catch (e) {
        // Avoid trapping the user in a close loop.
        NotificationManager.instance.error(
          'Failed to save encrypted database: $e',
        );
      }
    } else {
      try {
        await ref.read(requireDatabaseProvider).close();
      } catch (e) {
        // Ignore close errors on shutdown, but log for debugging
        AppLog.d('Database close on shutdown failed: $e');
      }
    }
  }

  @override
  void onWindowClose() async {
    if (_isClosingWindow) {
      return;
    }

    final isPreventClose = await windowManager.isPreventClose();
    if (!isPreventClose) return;

    _isClosingWindow = true;

    try {
      await windowManager.hide();
    } catch (_) {
      // Best effort only.
    }

    try {
      await _cleanupOnClose();
    } finally {
      try {
        await windowManager.setPreventClose(false);
        await windowManager.close();
      } catch (_) {
        await windowManager.destroy();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final currentNav = ref.watch(currentNavProvider);
    final shellSettings = ref.watch(appShellSettingsProvider);

    ref.listen<UpdatesSettings>(updatesSettingsProvider, (previous, next) {
      if (previous == null) {
        return;
      }

      if (previous.autoCheckEnabled != next.autoCheckEnabled ||
          previous.autoCheckIntervalMinutes != next.autoCheckIntervalMinutes) {
        _scheduleNextAutoUpdateCheck();
      }
    });

    NotificationManager.instance.setEnabled(shellSettings.notificationsEnabled);

    final navPosition = shellSettings.navBarPosition;
    final navAppearance = shellSettings.navBarAppearance;
    final gradientAnimation = shellSettings.gradientAnimation;
    final navCollapsed = shellSettings.navBarCollapsed;

    // Keep the expanded vertical rail compact while preserving button spacing.
    final navWidth = navCollapsed
      ? nav_panel.kNavigationPanelCollapsedWidth
      : nav_panel.kNavigationPanelExpandedWidth;

    final navItems = NavItem.values
        .map(
          (item) => nav_panel.NavItem(
            label: item.label,
            icon: item.unselectedIcon,
            selectedIcon: item.selectedIcon,
            pulsate:
                currentNav != item &&
                ref.watch(
                  pageNotificationsProvider.select((s) => s.contains(item)),
                ),
          ),
        )
        .toList(growable: false);

    // Check if batch fetch is active
    final batchFetchActive = ref.watch(
      batchFetchProvider.select((s) => s.isActive),
    );

    final navigationPanel = nav_panel.NavigationPanel(
      key: const ValueKey('navigation-panel'),
      items: navItems,
      selectedIndex: currentNav.index,
      onItemSelected: (index) {
        final targetNav = NavItem.values[index];
        // Block navigation to Add Games page during batch fetch
        if (batchFetchActive && targetNav == NavItem.addGames) {
          NotificationManager.instance.warning(
            'Cannot add games while Steam data fetch is in progress',
          );
          return;
        }
        // Visiting a page acknowledges its pending pulse notification.
        ref.read(pageNotificationsProvider.notifier).remove(targetNav);
        ref.read(currentNavProvider.notifier).setNav(targetNav);
      },
      theme: theme,
      position: navPosition,
      appearance: navAppearance,
      gradientAnimation: gradientAnimation,
      lockedIndices: batchFetchActive ? {NavItem.addGames.index} : {},
    );

    final animatedSideNavigationPanel = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      width: navWidth,
      child: navigationPanel,
    );

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            HardwareKeyboard.instance.isControlPressed &&
            HardwareKeyboard.instance.isAltPressed &&
            event.logicalKey == LogicalKeyboardKey.keyD) {
          DevWindowOverlay.toggle(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: theme.background,
        body: Stack(
          children: [
            Column(
              children: [
                // Custom title bar
                _TitleBar(theme: theme),

                // Main content with configurable navigation
                Expanded(
                  child: switch (navPosition) {
                    NavBarPosition.left => Row(
                      children: [
                        animatedSideNavigationPanel,
                        // Thin animated gradient separator on the inner edge
                        AnimatedGradientBar(
                          theme: theme,
                          animationStyle: gradientAnimation,
                          isVertical: true,
                          width: 6,
                        ),
                        Expanded(child: _buildPagesStack(currentNav)),
                      ],
                    ),
                    NavBarPosition.right => Row(
                      children: [
                        Expanded(child: _buildPagesStack(currentNav)),
                        // Thin animated gradient separator on the inner edge
                        AnimatedGradientBar(
                          theme: theme,
                          animationStyle: gradientAnimation,
                          isVertical: true,
                          width: 6,
                        ),
                        animatedSideNavigationPanel,
                      ],
                    ),
                    NavBarPosition.top => Column(
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: navigationPanel,
                        ),
                        AnimatedGradientBar(
                          theme: theme,
                          animationStyle: gradientAnimation,
                          isVertical: false,
                          height: 6,
                        ),
                        Expanded(child: _buildPagesStack(currentNav)),
                      ],
                    ),
                    NavBarPosition.bottom => Column(
                      children: [
                        Expanded(child: _buildPagesStack(currentNav)),
                        AnimatedGradientBar(
                          theme: theme,
                          animationStyle: gradientAnimation,
                          isVertical: false,
                          height: 6,
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: navigationPanel,
                        ),
                      ],
                    ),
                  },
                ),
              ],
            ),

            // Toast notifications overlay
            NotificationOverlay(
              theme: theme,
              position: NotificationManager.instance.position,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagesStack(NavItem currentNav) {
    if (_kDisablePersistentPages) {
      // Rebuild the currently active page each time. This is useful for
      // debugging or temporarily disabling the normal IndexedStack behavior.
      switch (currentNav) {
        case NavItem.home:
          return const HomePage();
        case NavItem.addGames:
          return const AddGamesPage();
        case NavItem.updates:
          return const UpdatePage();
        case NavItem.settings:
          return const SettingsPage();
      }
    }

    // Keep all primary pages alive so their UI state (scroll, selections, etc.)
    // is preserved when switching between navigation items.
    //
    // TickerMode(enabled: false) pauses ALL ticker-based animations (timers,
    // AnimationControllers, custom Tickers) on pages that are not currently
    // visible. This prevents off-screen pages from consuming CPU/GPU resources
    // during window resize and other rendering work. AnimatedGradientBar
    // instances — including the gradient preview cards on the Settings page —
    // already respect TickerMode.of(context) in their _canAnimate check, so
    // they stop automatically when their page is not focused.
    //
    // RepaintBoundary isolates each page's raster layer: repaints in the active
    // page do not cascade into off-screen pages, and vice versa, reducing GPU
    // work especially during window resize and animation.
    return IndexedStack(
      index: currentNav.index,
      children: NavItem.values.map((item) {
        final isActive = item == currentNav;
        return TickerMode(
          enabled: isActive,
          child: RepaintBoundary(
            child: switch (item) {
              NavItem.home => const HomePage(),
              NavItem.addGames => const AddGamesPage(),
              NavItem.updates => const UpdatePage(),
              NavItem.settings => const SettingsPage(),
            },
          ),
        );
      }).toList(),
    );
  }

  // Backwards-compatible single-page helper (still used by some tests/hooks)
  // Kept for compatibility with callers/tests that expect a single-page builder.
  // IndexedStack is used for normal navigation to preserve page state.
  // ignore: unused_element
  Widget _buildPage(NavItem nav) {
    switch (nav) {
      case NavItem.home:
        return const HomePage();
      case NavItem.addGames:
        return const AddGamesPage();
      case NavItem.updates:
        return const UpdatePage();
      case NavItem.settings:
        return const SettingsPage();
    }
  }
}

/// Custom title bar
// Visible for tests only: a public wrapper that creates the private title bar.
// Keeping the implementation class private avoids exporting internal helpers
// from the scaffold file. Unit tests may need to instantiate just the title bar
// without constructing the full scaffold, so use this helper.
Widget buildTitleBarForTest(AppThemeData theme) {
  return Material(child: _TitleBar(theme: theme));
}

class _TitleBar extends ConsumerWidget {
  const _TitleBar({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showFpsCounter = ref.watch(
      settingsProvider.select(
        (s) =>
            (s[SettingsKeys.showFpsCounter] as bool?) ??
            DefaultSettings.showFpsCounter,
      ),
    );

    // the dragging/ double‑tap region intentionally excludes the window buttons
    // so that their taps are delivered immediately rather than being delayed by
    // the ancestor gesture recognizer. an Expanded makes it stretch to take up
    // all remaining space.
    return Container(
      key: const Key('title-bar'),
      height: 32,
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(bottom: BorderSide(color: theme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              behavior: HitTestBehavior.translucent,
              child: Row(
                children: [
                  // App icon and title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(Icons.gamepad, size: 16, color: theme.accent),
                        const SizedBox(width: 8),
                        Text(
                          AppConstants.appTitle,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Menu button with Import/Export options
                  _MenuButton(theme: theme),

                  const Spacer(),

                  if (showFpsCounter)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _TitleBarFpsCounter(theme: theme),
                    ),
                ],
              ),
            ),
          ),

          // Window controls remain outside of the gesture area that handles
          // double taps so they are responsive immediately.
          _WindowButton(
            icon: Icons.remove,
            theme: theme,
            onPressed: () => windowManager.minimize(),
          ),
          _WindowButton(
            icon: Icons.crop_square,
            theme: theme,
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _WindowButton(
            icon: Icons.close,
            theme: theme,
            hoverColor: Colors.red,
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _TitleBarFpsCounter extends StatefulWidget {
  const _TitleBarFpsCounter({required this.theme});

  final AppThemeData theme;

  @override
  State<_TitleBarFpsCounter> createState() => _TitleBarFpsCounterState();
}

class _TitleBarFpsCounterState extends State<_TitleBarFpsCounter>
    with SingleTickerProviderStateMixin {
  static const int _fpsUpdateIntervalMs = 250;

  late final Ticker _ticker;
  Duration? _windowStart;
  int _ticksInWindow = 0;
  int _fps = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _windowStart ??= elapsed;
    _ticksInWindow++;

    final elapsedMs = (elapsed - _windowStart!).inMilliseconds;
    if (elapsedMs < _fpsUpdateIntervalMs) return;

    final nextFps = ((_ticksInWindow * 1000) / elapsedMs).round();
    _ticksInWindow = 0;
    _windowStart = elapsed;

    if (!mounted || nextFps == _fps) return;
    setState(() => _fps = nextFps);
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${_fps > 0 ? _fps : '--'} FPS',
      style: TextStyle(
        color: widget.theme.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Menu button with Import/Export options
class _MenuButton extends StatefulWidget {
  const _MenuButton({required this.theme});

  final AppThemeData theme;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  Future<void> _openMenu() async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      button.localToGlobal(Offset.zero) & button.size,
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<String>(
      context: context,
      position: position,
      color: widget.theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: widget.theme.border),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'import',
          child: Row(
            children: [
              Icon(
                Icons.file_download,
                size: 18,
                color: widget.theme.textPrimary,
              ),
              const SizedBox(width: 12),
              Text(
                'Import Database',
                style: TextStyle(color: widget.theme.textPrimary),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'export',
          child: Row(
            children: [
              Icon(
                Icons.file_upload,
                size: 18,
                color: widget.theme.textPrimary,
              ),
              const SizedBox(width: 12),
              Text(
                'Export Database',
                style: TextStyle(color: widget.theme.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );

    if (!mounted) return;

    if (selected == 'import') {
      showImportDialog(context);
    } else if (selected == 'export') {
      showExportDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) {
          if (_isPressed) {
            _openMenu();
          }
          setState(() => _isPressed = false);
        },
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: Container(
          width: 36,
          height: 32,
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.theme.accent.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.menu,
            size: 16,
            color: _isHovered
                ? widget.theme.accent
                : widget.theme.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Window control button
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.theme,
    required this.onPressed,
    this.hoverColor,
  });

  final IconData icon;
  final AppThemeData theme;
  final VoidCallback onPressed;
  final Color? hoverColor;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 32,
          color: _isHovered
              ? (widget.hoverColor ?? widget.theme.accent).withValues(
                  alpha: 0.2,
                )
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered
                ? (widget.hoverColor ?? widget.theme.accent)
                : widget.theme.textSecondary,
          ),
        ),
      ),
    );
  }
}
