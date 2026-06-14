/// Main application scaffold - root widget with navigation
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
import '../core/models/device_sync_models.dart';
import 'dialogs/device_sync_dialog.dart';
import 'dialogs/import_export_dialog.dart';
import 'pages/add_games_page.dart';
import 'pages/settings_sections/database_section.dart'
    show showChangeDatabaseDialog;
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/update_page.dart';
import 'widgets/navigation_panel.dart' as nav_panel;
import 'widgets/animated_gradient_bar.dart';
import 'widgets/app_progress_indicator.dart';
import 'widgets/dev_window.dart';
import 'widgets/dialog_helpers.dart';
import 'widgets/notification_system.dart';
import 'widgets/pair_code_widgets.dart';
import 'widgets/popup_menu_helpers.dart';

const int _kLargeLibraryNavAnimationThreshold = 250;
const double _kDetachedGradientBarExtent = 6.0;

enum _ShellPageTransitionStyle {
  pageScroll,
  fadeThrough,
  slideFade,
  sharedAxis,
}

const _ShellPageTransitionStyle _kShellPageTransitionStyle =
    _ShellPageTransitionStyle.slideFade;

/// Navigation items5
/// Main app scaffold
class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold>
    with WindowListener, WidgetsBindingObserver {
  Timer? _windowSaveDebounce;
  bool _applyingSavedWindowState = false;
  Timer? _autoBackupTimer;
  Timer? _autoUpdateTimer;
  bool _isClosingWindow = false;
  bool _windowMaximized = false;
  NavBarPosition? _lastNavPosition;
  NavItem? _previousPageNav;
  bool _navCollapseToggled = false;
  Timer? _navCollapseAnimTimer;
  final Set<String> _handledPairRequestPrompts = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _applyMobileSystemUiMode();
    _initWindow();
    _initAutoBackup();
    _initAutoUpdateChecks();
  }

  @override
  void dispose() {
    _cancelAllTimers();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  void _cancelAllTimers() {
    _windowSaveDebounce = _cancelTimer(_windowSaveDebounce);
    _autoBackupTimer = _cancelTimer(_autoBackupTimer);
    _autoUpdateTimer = _cancelTimer(_autoUpdateTimer);
    _navCollapseAnimTimer = _cancelTimer(_navCollapseAnimTimer);
  }

  Timer? _cancelTimer(Timer? timer) {
    timer?.cancel();
    return null;
  }

  Timer _replaceTimer(
    Timer? timer,
    Duration duration,
    void Function() callback,
  ) {
    timer?.cancel();
    return Timer(duration, callback);
  }

  Timer _replacePeriodicTimer(
    Timer? timer,
    Duration duration,
    void Function(Timer) callback,
  ) {
    timer?.cancel();
    return Timer.periodic(duration, callback);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyMobileSystemUiMode();
    }
  }

  void _applyMobileSystemUiMode() {
    if (!Platform.isAndroid) {
      return;
    }

    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
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
    final shellSettings = ref.read(appShellSettingsProvider);
    final autoBackupEnabled = shellSettings.autoBackupEnabled;
    final intervalMinutes = shellSettings.autoBackupIntervalMinutes;

    if (autoBackupEnabled && intervalMinutes > 0) {
      final interval = Duration(minutes: intervalMinutes);

      // Update the next backup time provider
      ref
          .read(nextAutoBackupTimeProvider.notifier)
          .setNextBackupTime(DateTime.now().add(interval));

      _autoBackupTimer = _replacePeriodicTimer(_autoBackupTimer, interval, (
        _,
      ) async {
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
      _autoBackupTimer = _cancelTimer(_autoBackupTimer);
      // Clear next backup time if disabled
      ref.read(nextAutoBackupTimeProvider.notifier).setNextBackupTime(null);
    }
  }

  void _scheduleNextAutoUpdateCheck({bool useStartupDelay = false}) {
    final updatesSettings = ref.read(updatesSettingsProvider);
    if (!updatesSettings.autoCheckEnabled) {
      _autoUpdateTimer = _cancelTimer(_autoUpdateTimer);
      ref.read(nextAutoUpdateTimeProvider.notifier).setNextUpdateTime(null);
      return;
    }

    final delay = useStartupDelay
        ? const Duration(seconds: 3)
        : const Duration(minutes: kDefaultAutoUpdateIntervalMinutes);

    ref
        .read(nextAutoUpdateTimeProvider.notifier)
        .setNextUpdateTime(DateTime.now().add(delay));

    _autoUpdateTimer = _replaceTimer(_autoUpdateTimer, delay, () async {
      if (!mounted) return;

      try {
        final updateState = ref.read(updateProvider);
        if (canRunAutomaticUpdateCheck(updateState)) {
          await ref.read(updateProvider.notifier).checkForUpdates();
        }
      } catch (e) {
        AppLog.w('Automatic update check failed', error: e);
      }

      if (!mounted) return;
      _scheduleNextAutoUpdateCheck();
    });
  }

  bool get _hasDesktopWindowControls =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _initWindow() async {
    if (!_hasDesktopWindowControls) return;

    await windowManager.ensureInitialized();
    // Prevent immediate close so we can persist encrypted DB changes.
    await windowManager.setPreventClose(true);

    _applyingSavedWindowState = true;
    final settings = ref.read(appShellSettingsProvider);

    // Always use the primary display to avoid off-screen launches.
    final hasSaved = settings.windowX != null && settings.windowY != null;
    final primary = await screenRetriever.getPrimaryDisplay();
    final targetDisplay = primary;

    final targetVisible = targetDisplay.visibleSize ?? targetDisplay.size;
    final targetOrigin = targetDisplay.visiblePosition ?? Offset.zero;

    final windowSize = Size(
      (hasSaved ? settings.windowWidth : kDefaultWindowWidth).clamp(
        kMinWindowWidth,
        targetVisible.width,
      ),
      (hasSaved ? settings.windowHeight : kDefaultWindowHeight).clamp(
        kMinWindowHeight,
        targetVisible.height,
      ),
    );

    final windowPos =
        targetOrigin +
        Offset(
          (targetVisible.width - windowSize.width) / 2,
          (targetVisible.height - windowSize.height) / 2,
        );

    final windowOptions = WindowOptions(
      size: windowSize,
      minimumSize: const Size(kMinWindowWidth, kMinWindowHeight),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: AppConstants.appTitle,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPosition(windowPos);
      if (settings.windowMaximized) await windowManager.maximize();
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

  void _scheduleSaveWindowState() {
    if (_applyingSavedWindowState) return;

    _windowSaveDebounce = _replaceTimer(
      _windowSaveDebounce,
      const Duration(milliseconds: 250),
      () async {
        try {
          final size = await windowManager.getSize();
          final pos = await windowManager.getPosition();
          final maximized = await windowManager.isMaximized();

          final settingsNotifier = ref.read(settingsProvider.notifier);
          await settingsNotifier.setSetting(
            SettingsKeys.windowWidth,
            size.width,
          );
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
      },
    );
  }

  @override
  void onWindowResized() => _scheduleSaveWindowState();

  @override
  void onWindowMoved() => _scheduleSaveWindowState();

  @override
  void onWindowMaximize() {
    _scheduleSaveWindowState();
    if (mounted && Platform.isLinux) setState(() => _windowMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    _scheduleSaveWindowState();
    if (mounted && Platform.isLinux) setState(() => _windowMaximized = false);
  }

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
    final databaseRevision = ref.watch(
      databaseNotifierProvider.select((state) => state.revision),
    );
    final platform = Theme.of(context).platform;
    final isMobilePlatform =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final viewportWidth = MediaQuery.sizeOf(context).width;

    ref.listen<UpdatesSettings>(updatesSettingsProvider, (previous, next) {
      if (previous == null) {
        return;
      }

      if (previous.autoCheckEnabled != next.autoCheckEnabled) {
        _scheduleNextAutoUpdateCheck();
      }
    });

    ref.listen<NavItem>(currentNavProvider, (previous, next) {
      if (previous == null || previous == next) return;
      _previousPageNav = previous;
    });

    // When the user explicitly toggles collapse/expand, temporarily lift the
    // large-library animation skip so the panel always animates smoothly.
    ref.listen<bool>(
      appShellSettingsProvider.select((s) => s.navBarCollapsed),
      (previous, next) {
        if (previous == null || previous == next) return;
        setState(() => _navCollapseToggled = true);
        _navCollapseAnimTimer = _replaceTimer(
          _navCollapseAnimTimer,
          kNavPanelMotionAnimation,
          () {
            if (mounted) setState(() => _navCollapseToggled = false);
          },
        );
      },
    );

    ref.listen(deviceSyncProvider, (previous, next) {
      final snapshot = next.asData?.value;
      if (snapshot == null) {
        return;
      }

      final activeIds = snapshot.pendingPairRequests
          .map((r) => r.requestId)
          .toSet();
      _handledPairRequestPrompts.removeWhere((id) => !activeIds.contains(id));

      if (snapshot.pendingPairRequests.isEmpty) {
        return;
      }

      for (final request in snapshot.pendingPairRequests) {
        if (_handledPairRequestPrompts.contains(request.requestId)) {
          continue;
        }
        _handledPairRequestPrompts.add(request.requestId);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final latest = ref.read(deviceSyncProvider).asData?.value;
          final stillPending =
              latest?.pendingPairRequests.any(
                (pending) => pending.requestId == request.requestId,
              ) ??
              false;
          if (!stillPending) {
            _handledPairRequestPrompts.remove(request.requestId);
            return;
          }
          _showIncomingPairRequestPrompt(context, request);
        });
        break;
      }
    });

    final navPosition = shellSettings.navBarPosition;
    final navAppearance = shellSettings.navBarAppearance;
    final gradientAnimation = shellSettings.gradientAnimation;
    final useInnerNavGradient = shellSettings.navPanelGradientBar;
    final isVerticalNavBase =
        navPosition == NavBarPosition.left ||
        navPosition == NavBarPosition.right;
    final baseNavCollapsed = isMobilePlatform || shellSettings.navBarCollapsed;
    final baseNavWidth = useInnerNavGradient && isVerticalNavBase
        ? (baseNavCollapsed
              ? nav_panel.kNavigationPanelInnerGradientCollapsedWidth
              : nav_panel.kNavigationPanelInnerGradientExpandedWidth)
        : (baseNavCollapsed
              ? nav_panel.kNavigationPanelCollapsedWidth
              : nav_panel.kNavigationPanelExpandedWidth);
    final projectedContentWidth = switch (navPosition) {
      NavBarPosition.left || NavBarPosition.right =>
        viewportWidth -
            (baseNavWidth +
                (useInnerNavGradient ? 0.0 : _kDetachedGradientBarExtent)),
      NavBarPosition.top || NavBarPosition.bottom => viewportWidth,
    };
    final isVeryNarrowLayout =
        projectedContentWidth < kVeryNarrowLayoutBreakpoint;
    final forceCollapsedNav = isMobilePlatform || isVeryNarrowLayout;
    final navCollapsed = forceCollapsedNav || shellSettings.navBarCollapsed;
    final filteredGameCount = currentNav == NavItem.home
        ? ref.watch(gamesProvider.select((s) => s.filteredGames.length))
        : 0;
    final skipNavSizeAnimationForLargeLibrary =
        !_navCollapseToggled &&
        currentNav == NavItem.home &&
        filteredGameCount >= _kLargeLibraryNavAnimationThreshold;
    final navPositionChanged =
        _lastNavPosition != null && _lastNavPosition != navPosition;
    _lastNavPosition = navPosition;
    final navMotionAnimationDuration = skipNavSizeAnimationForLargeLibrary
        ? Duration.zero
        : kNavPanelMotionAnimation;

    // Keep the expanded vertical rail compact while preserving button spacing.
    final isVerticalNav =
        navPosition == NavBarPosition.left ||
        navPosition == NavBarPosition.right;
    final navWidth = useInnerNavGradient && isVerticalNav
        ? (navCollapsed
              ? nav_panel.kNavigationPanelInnerGradientCollapsedWidth
              : nav_panel.kNavigationPanelInnerGradientExpandedWidth)
        : (navCollapsed
              ? nav_panel.kNavigationPanelCollapsedWidth
              : nav_panel.kNavigationPanelExpandedWidth);
    final navPanelHorizontalExtent = useInnerNavGradient
        ? nav_panel.kNavigationPanelInnerGradientExtent
        : nav_panel.kNavigationPanelHorizontalExtent;
    // Width for the always-present left/right slots. Computed independently of
    // the active position so an exiting side panel keeps its correct size as it
    // slides out (not affected by a switch to a top/bottom position).
    final sideNavWidth = useInnerNavGradient
        ? (navCollapsed
              ? nav_panel.kNavigationPanelInnerGradientCollapsedWidth
              : nav_panel.kNavigationPanelInnerGradientExpandedWidth)
        : (navCollapsed
              ? nav_panel.kNavigationPanelCollapsedWidth
              : nav_panel.kNavigationPanelExpandedWidth);

    final updateIsActive = ref.watch(
      updateProvider.select((s) => s.isChecking || s.isDownloading),
    );
    final updateIsReady = ref.watch(
      updateProvider.select((s) => s.downloadedFilePath != null),
    );

    final navItems = NavItem.values
        .map((item) {
          final hasNotification =
              currentNav != item &&
              ref.watch(
                pageNotificationsProvider.select((s) => s.contains(item)),
              );
          if (item == NavItem.updates) {
            final showAvailableDownloadIcon = hasNotification && !updateIsReady;
            final iconData = updateIsReady
                ? Icons.file_download_done
                : showAvailableDownloadIcon
                ? Icons.download_rounded
                : item.unselectedIcon;
            return nav_panel.NavItem(
              label: item.label,
              icon: iconData,
              selectedIcon: iconData,
              iconBuilder: (color, size) => _UpdateNavIcon(
                iconData: iconData,
                isActive: updateIsActive,
                useAccentColor: showAvailableDownloadIcon || updateIsReady,
                color: color,
                accentColor: theme.accent,
                size: size,
              ),
            );
          }
          return nav_panel.NavItem(
            label: item.label,
            icon: item.unselectedIcon,
            selectedIcon: item.selectedIcon,
          );
        })
        .toList(growable: false);

    // Check if batch fetch is active
    final batchFetchActive = ref.watch(
      batchFetchProvider.select((s) => s.isActive),
    );

    // Shared item-selection handler for all four persistent nav panel instances.
    void onNavItemSelected(int index) {
      final targetNav = NavItem.values[index];
      final syncReceiveInFlight = ref
          .read(deviceSyncServiceProvider)
          .isReceiverSyncInFlight;
      // Block navigation to Add Games page during batch fetch
      if (syncReceiveInFlight && targetNav == NavItem.addGames) {
        NotificationManager.instance.warning(
          'Cannot add games while device sync is in progress',
        );
        return;
      }
      if (batchFetchActive && targetNav == NavItem.addGames) {
        NotificationManager.instance.warning(
          'Cannot add games while Steam data fetch is in progress',
        );
        return;
      }
      // Visiting a page acknowledges its pending nav notification state.
      ref.read(pageNotificationsProvider.notifier).remove(targetNav);
      ref.read(currentNavProvider.notifier).setNav(targetNav);
    }

    // Returns a NavigationPanel fixed to [pos]. All four instances share the
    // same Riverpod state (selectedIndex, theme, etc.) so they always mirror
    // the same selection while physically living at different screen edges.
    nav_panel.NavigationPanel buildNavPanel(NavBarPosition pos) =>
        nav_panel.NavigationPanel(
          key: ValueKey('nav-panel-${pos.name}'),
          items: navItems,
          selectedIndex: currentNav.index,
          onItemSelected: onNavItemSelected,
          theme: theme,
          position: pos,
          appearance: navAppearance,
          gradientAnimation: gradientAnimation,
          forceCollapsed: forceCollapsedNav,
          lockedIndices: batchFetchActive ? {NavItem.addGames.index} : {},
        );

    final pagesStack = _buildPagesStack(
      currentNav,
      databaseRevision,
      isVerticalNav,
      isVeryNarrowLayout,
    );

    Widget buildNavSlot(NavBarPosition position) {
      final isVertical =
          position == NavBarPosition.left || position == NavBarPosition.right;
      final panel = buildNavPanel(position);
      final panelChild = isVertical
          ? AnimatedContainer(
              duration: navMotionAnimationDuration,
              curve: kNavPanelMotionCurve,
              width: sideNavWidth,
              child: panel,
            )
          : panel;
      final slotChild = useInnerNavGradient
          ? panelChild
          : _NavPanelWithDetachedGradient(
              position: position,
              theme: theme,
              gradientAnimation: gradientAnimation,
              panel: panelChild,
            );
      final slotHorizontalExtent =
          navPanelHorizontalExtent +
          (useInnerNavGradient ? 0.0 : _kDetachedGradientBarExtent);

      return switch (position) {
        NavBarPosition.left => Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: _NavPositionSlot(
            key: const ValueKey('nav-slot-left'),
            position: position,
            isActive: navPosition == position,
            child: slotChild,
          ),
        ),
        NavBarPosition.right => Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: _NavPositionSlot(
            key: const ValueKey('nav-slot-right'),
            position: position,
            isActive: navPosition == position,
            child: slotChild,
          ),
        ),
        NavBarPosition.top => Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: slotHorizontalExtent,
          child: _NavPositionSlot(
            key: const ValueKey('nav-slot-top'),
            position: position,
            isActive: navPosition == position,
            child: slotChild,
          ),
        ),
        NavBarPosition.bottom => Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: slotHorizontalExtent,
          child: _NavPositionSlot(
            key: const ValueKey('nav-slot-bottom'),
            position: position,
            isActive: navPosition == position,
            child: slotChild,
          ),
        ),
      };
    }

    final navLayoutAnimationDuration = navPositionChanged
        ? kNavPanelMotionAnimation
        : navMotionAnimationDuration;
    final pageInsets = switch (navPosition) {
      NavBarPosition.left => EdgeInsets.only(
        left:
            navWidth +
            (useInnerNavGradient ? 0.0 : _kDetachedGradientBarExtent),
      ),
      NavBarPosition.right => EdgeInsets.only(
        right:
            navWidth +
            (useInnerNavGradient ? 0.0 : _kDetachedGradientBarExtent),
      ),
      NavBarPosition.top => EdgeInsets.only(
        top:
            navPanelHorizontalExtent +
            (useInnerNavGradient ? 0.0 : _kDetachedGradientBarExtent),
      ),
      NavBarPosition.bottom => EdgeInsets.only(
        bottom:
            navPanelHorizontalExtent +
            (useInnerNavGradient ? 0.0 : _kDetachedGradientBarExtent),
      ),
    };
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
                if (_hasDesktopWindowControls) ...[_TitleBar(theme: theme)],

                // Main content with configurable navigation
                Expanded(
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: AnimatedPadding(
                            duration: navLayoutAnimationDuration,
                            curve: kNavPanelMotionCurve,
                            padding: pageInsets,
                            child: pagesStack,
                          ),
                        ),
                        ...NavBarPosition.values.map(buildNavSlot),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Toast notifications overlay
            NotificationOverlay(
              theme: theme,
              position: NotificationManager.instance.position,
            ),

            // Linux: custom edge resize handles (TitleBarStyle.hidden removes GTK borders)
            if (Platform.isLinux && !_windowMaximized)
              const _LinuxResizeFrame(),
          ],
        ),
      ),
    );
  }

  Widget _buildPagesStack(
    NavItem currentNav,
    int databaseRevision,
    bool isVerticalNav,
    bool isVeryNarrowLayout,
  ) {
    final activeNavKey = ValueKey<String>('active-nav-${currentNav.name}');

    return AnimatedSwitcher(
      duration: kPageTransition,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (previousChildren.isNotEmpty) previousChildren.last,
            ...?currentChild == null ? null : [currentChild],
          ],
        ),
      ),
      transitionBuilder: (child, animation) => _buildPageTransition(
        child: child,
        animation: animation,
        currentNav: currentNav,
        currentNavKey: activeNavKey,
        isVerticalNav: isVerticalNav,
      ),
      child: KeyedSubtree(
        key: activeNavKey,
        child: RepaintBoundary(
          child: _buildActivePage(
            currentNav,
            databaseRevision,
            isVeryNarrowLayout,
          ),
        ),
      ),
    );
  }

  Widget _buildActivePage(
    NavItem currentNav,
    int databaseRevision,
    bool isVeryNarrowLayout,
  ) {
    return switch (currentNav) {
      NavItem.home => HomePage(
        key: ValueKey<String>('home-page-$databaseRevision'),
        isVeryNarrowLayout: isVeryNarrowLayout,
      ),
      NavItem.addGames => AddGamesPage(
        key: ValueKey<String>('add-games-page-$databaseRevision'),
      ),
      NavItem.updates => UpdatePage(
        key: ValueKey<String>('update-page-$databaseRevision'),
      ),
      NavItem.settings => SettingsPage(
        key: ValueKey<String>('settings-page-$databaseRevision'),
      ),
    };
  }

  Widget _buildPageTransition({
    required Widget child,
    required Animation<double> animation,
    required NavItem currentNav,
    required ValueKey<String> currentNavKey,
    required bool isVerticalNav,
  }) {
    final isIncoming = child.key == currentNavKey;
    final previousIndex = (_previousPageNav ?? currentNav).index;
    final direction = currentNav.index >= previousIndex ? 1.0 : -1.0;

    return switch (_kShellPageTransitionStyle) {
      _ShellPageTransitionStyle.pageScroll => _buildPageScrollTransition(
        child: child,
        animation: animation,
        isIncoming: isIncoming,
        isVerticalNav: isVerticalNav,
        direction: direction,
      ),
      _ShellPageTransitionStyle.fadeThrough => _buildFadeThroughTransition(
        child: child,
        animation: animation,
        isIncoming: isIncoming,
      ),
      _ShellPageTransitionStyle.slideFade => _buildSlideFadeTransition(
        child: child,
        animation: animation,
        isIncoming: isIncoming,
        isVerticalNav: isVerticalNav,
        direction: direction,
      ),
      _ShellPageTransitionStyle.sharedAxis => _buildSharedAxisTransition(
        child: child,
        animation: animation,
        isIncoming: isIncoming,
      ),
    };
  }

  Widget _buildPageScrollTransition({
    required Widget child,
    required Animation<double> animation,
    required bool isIncoming,
    required bool isVerticalNav,
    required double direction,
  }) {
    final Offset beginOffset;
    final Offset outgoingOffset;
    if (isVerticalNav) {
      // Vertical nav (left/right): slide pages vertically
      beginOffset = Offset(0, direction);
      outgoingOffset = Offset(0, -direction);
    } else {
      // Horizontal nav (top/bottom): slide pages horizontally
      beginOffset = Offset(direction, 0);
      outgoingOffset = Offset(-direction, 0);
    }
    final position = animation.drive(
      Tween<Offset>(
        begin: isIncoming ? beginOffset : outgoingOffset,
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
    );

    return SlideTransition(position: position, child: child);
  }

  Animation<double> _buildScaleAnimation({
    required Animation<double> animation,
    required double begin,
    required Curve curve,
  }) {
    return animation.drive(
      Tween<double>(begin: begin, end: 1.0).chain(CurveTween(curve: curve)),
    );
  }

  Widget _buildFadeScaleTransition({
    required Widget child,
    required Animation<double> opacity,
    required Animation<double> scale,
  }) {
    return FadeTransition(
      opacity: opacity,
      child: ScaleTransition(scale: scale, child: child),
    );
  }

  Widget _buildFadeThroughTransition({
    required Widget child,
    required Animation<double> animation,
    required bool isIncoming,
  }) {
    final opacity = CurvedAnimation(
      parent: animation,
      curve: isIncoming
          ? const Interval(0.18, 1.0, curve: Curves.easeOutCubic)
          : const Interval(0.0, 0.55, curve: Curves.easeInCubic),
    );

    final scale = _buildScaleAnimation(
      animation: animation,
      begin: isIncoming ? 0.985 : 1.0,
      curve: isIncoming ? Curves.easeOutCubic : Curves.linear,
    );

    return _buildFadeScaleTransition(
      child: child,
      opacity: opacity,
      scale: scale,
    );
  }

  Widget _buildSlideFadeTransition({
    required Widget child,
    required Animation<double> animation,
    required bool isIncoming,
    required bool isVerticalNav,
    required double direction,
  }) {
    final incomingOffset = isVerticalNav
        ? Offset(0, 0.035 * direction)
        : Offset(0.035 * direction, 0);
    final outgoingOffset = Offset(
      -incomingOffset.dx * 0.55,
      -incomingOffset.dy * 0.55,
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(
            begin: isIncoming ? incomingOffset : outgoingOffset,
            end: Offset.zero,
          ).chain(
            CurveTween(
              curve: isIncoming ? Curves.easeOutCubic : Curves.easeInCubic,
            ),
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _buildSharedAxisTransition({
    required Widget child,
    required Animation<double> animation,
    required bool isIncoming,
  }) {
    final scale = _buildScaleAnimation(
      animation: animation,
      begin: isIncoming ? 0.96 : 1.02,
      curve: isIncoming ? Curves.easeOutCubic : Curves.easeInCubic,
    );

    return _buildFadeScaleTransition(
      child: child,
      opacity: animation,
      scale: scale,
    );
  }

  Future<void> _showIncomingPairRequestPrompt(
    BuildContext context,
    PendingPairRequest request,
  ) async {
    if (!context.mounted) return;
    final result = await showDialog<_IncomingPairDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _IncomingPairDialog(request: request),
    );
    if (!context.mounted || result != null) {
      return;
    }

    // Manual dismiss (Esc / window close button) returns null.
    // Treat that as an explicit decline so the initiator isn't left waiting
    // for request timeout.
    try {
      await ref.read(deviceSyncProvider.notifier).respondToPairRequest(
            requestId: request.requestId,
            accept: false,
          );
    } catch (_) {
      // Request may already be resolved remotely.
    }
  }
}

enum _IncomingPairDialogResult { declined, resolved }

/// Dialog shown on the receiver side when an incoming pair request arrives.
///
/// Closes automatically when the pairing session is resolved — trusted,
/// canceled, or timed out — via the service event stream.  MITM protection
/// is preserved: the entered code is encrypted with a key derived from an
/// x25519 DH exchange between the two devices' static key-pairs (HKDF +
/// AES-GCM), so a network-level attacker cannot intercept or forge it.
class _IncomingPairDialog extends ConsumerStatefulWidget {
  const _IncomingPairDialog({required this.request});
  final PendingPairRequest request;

  @override
  ConsumerState<_IncomingPairDialog> createState() =>
      _IncomingPairDialogState();
}

class _IncomingPairDialogState extends ConsumerState<_IncomingPairDialog> {
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
    _eventSub =
        ref.read(deviceSyncServiceProvider).syncEvents.listen((event) {
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
            Navigator.of(context).maybePop(_IncomingPairDialogResult.resolved);
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
          TextButton(
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
    Navigator.of(context).maybePop(_IncomingPairDialogResult.declined);
    try {
      await ref.read(deviceSyncProvider.notifier).respondToPairRequest(
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
      await ref.read(deviceSyncProvider.notifier).respondToPairRequest(
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

class _UpdateNavIcon extends StatelessWidget {
  const _UpdateNavIcon({
    required this.iconData,
    required this.isActive,
    required this.useAccentColor,
    required this.color,
    required this.accentColor,
    required this.size,
  });

  final IconData iconData;
  final bool isActive;
  final bool useAccentColor;
  final Color color;
  final Color accentColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: AnimatedSwitcher(
          duration: kFastAnimation,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeOut,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.center,
            children: [
              ...previousChildren,
              ...?currentChild == null ? null : [currentChild],
            ],
          ),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: isActive
              ? SizedBox(
                  key: const ValueKey('upd-active'),
                  width: size,
                  height: size,
                  child: AppCircularProgressIndicator(color: color),
                )
              : Icon(
                  iconData,
                  key: ValueKey('upd-${iconData.codePoint}-$useAccentColor'),
                  color: useAccentColor ? accentColor : color,
                  size: size,
                ),
        ),
      ),
    );
  }
}

/// Persistent slot that slide-animates in/out when [isActive] toggles.
/// Keeping all four position slots alive in the widget tree lets the outgoing
/// panel play its exit animation at the same time as the incoming panel slides
/// in, instead of the old panel instantly disappearing when the key changes.
class _NavPositionSlot extends StatefulWidget {
  const _NavPositionSlot({
    super.key,
    required this.position,
    required this.isActive,
    required this.child,
  });

  final NavBarPosition position;
  final bool isActive;
  final Widget child;

  @override
  State<_NavPositionSlot> createState() => _NavPositionSlotState();
}

class _NavPositionSlotState extends State<_NavPositionSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kNavPanelMotionAnimation,
    value: widget.isActive ? 1.0 : 0.0,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: kNavPanelMotionCurve,
  );
  // True while the panel is either visible or animating — keeps the subtree
  // mounted so the exit animation can play. Reset to false after the exit
  // animation fully completes, which unmounts the NavigationPanel.
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _visible = true;
    _controller.addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() => _visible = false);
    }
  }

  @override
  void didUpdateWidget(covariant _NavPositionSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        // setState guarantees the AnimatedBuilder is in the tree before the
        // first animation tick, so the panel starts fully off-screen and
        // slides in smoothly rather than appearing at its final position.
        setState(() => _visible = true);
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: !widget.isActive,
      child: _EdgeSlideTransition(
        position: widget.position,
        animation: _curve,
        child: widget.child,
      ),
    );
  }
}

class _EdgeSlideTransition extends StatelessWidget {
  const _EdgeSlideTransition({
    required this.position,
    required this.animation,
    required this.child,
  });

  final NavBarPosition position;
  final Animation<double> animation;
  final Widget child;

  Offset _startOffsetFor(NavBarPosition position) {
    return switch (position) {
      NavBarPosition.left => const Offset(-1, 0),
      NavBarPosition.right => const Offset(1, 0),
      NavBarPosition.top => const Offset(0, -1),
      NavBarPosition.bottom => const Offset(0, 1),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final startOffset = _startOffsetFor(position);
        final t = animation.value;
        return FractionalTranslation(
          translation: Offset(
            startOffset.dx * (1 - t),
            startOffset.dy * (1 - t),
          ),
          child: Opacity(opacity: 0.68 + (0.32 * t), child: child!),
        );
      },
    );
  }
}

class _NavPanelWithDetachedGradient extends StatelessWidget {
  const _NavPanelWithDetachedGradient({
    required this.position,
    required this.theme,
    required this.gradientAnimation,
    required this.panel,
  });

  final NavBarPosition position;
  final AppThemeData theme;
  final GradientAnimation gradientAnimation;
  final Widget panel;

  bool get _isVertical =>
      position == NavBarPosition.left || position == NavBarPosition.right;

  Widget _buildDetachedGradient() {
    return RepaintBoundary(
      child: _isVertical
          ? AnimatedGradientBar(
              theme: theme,
              animationStyle: gradientAnimation,
              isVertical: true,
              width: _kDetachedGradientBarExtent,
              flipWaveForLeftVertical: position == NavBarPosition.left,
            )
          : AnimatedGradientBar(
              theme: theme,
              animationStyle: gradientAnimation,
              isVertical: false,
              height: _kDetachedGradientBarExtent,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _buildDetachedGradient();

    if (_isVertical) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: position == NavBarPosition.left
            ? [panel, gradient]
            : [gradient, panel],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: position == NavBarPosition.top
          ? [panel, gradient]
          : [gradient, panel],
    );
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
                        const SizedBox(width: kElementHSpacing),
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
                  _SyncButton(theme: theme),

                  const Spacer(),
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
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      button.localToGlobal(Offset.zero) & button.size,
      Offset.zero & overlay.size,
    );

    final selected = await showAppMenu<String>(
      context: context,
      position: position,
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
        PopupMenuItem<String>(
          value: 'change_db',
          child: Row(
            children: [
              Icon(Icons.swap_horiz, size: 18, color: widget.theme.textPrimary),
              const SizedBox(width: 12),
              Text(
                'Change Database',
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
    } else if (selected == 'change_db') {
      showChangeDatabaseDialog(context, widget.theme);
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

class _SyncButton extends ConsumerStatefulWidget {
  const _SyncButton({required this.theme});

  final AppThemeData theme;

  @override
  ConsumerState<_SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends ConsumerState<_SyncButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  (IconData, Color) _iconForStatus(DeviceSyncStatus status) {
    switch (status) {
      case DeviceSyncStatus.discovering:
        return (Icons.radar, widget.theme.accent);
      case DeviceSyncStatus.connecting:
        return (Icons.link, widget.theme.accent);
      case DeviceSyncStatus.connected:
        return (Icons.link, widget.theme.secondary);
      case DeviceSyncStatus.syncing:
        return (Icons.sync, widget.theme.accent);
      case DeviceSyncStatus.error:
        return (Icons.link_off, widget.theme.error);
      case DeviceSyncStatus.idle:
        return (Icons.sync_disabled, widget.theme.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(deviceSyncProvider).asData?.value;
    final enabled = sync?.enabled ?? false;
    final status = sync?.status ?? DeviceSyncStatus.idle;
    var (iconData, activeColor) = _iconForStatus(status);
    final statusText = sync?.statusMessage?.toLowerCase() ?? '';
    final isUnpairNotice =
        statusText.contains('removed its pairing') ||
        statusText.contains('device removed');

    // Surface unpair events as a broken link icon to match sync dialog state.
    if (isUnpairNotice) {
      iconData = Icons.link_off;
      activeColor = widget.theme.textSecondary;
    }

    // When connected but DB files differ, show a broken link to signal out-of-sync.
    final hasMismatch = sync?.dbMismatchPeerIds.isNotEmpty ?? false;
    if (!isUnpairNotice && hasMismatch) {
      iconData = Icons.link_off;
      activeColor = Colors.orange;
    }

    final showBusyIndicator =
        status == DeviceSyncStatus.syncing ||
        status == DeviceSyncStatus.discovering ||
        status == DeviceSyncStatus.connecting;

    return Tooltip(
      message: 'Device Sync',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => setState(() => _isPressed = true),
          onPointerUp: (_) {
            if (_isPressed) {
              showDeviceSyncDialog(context);
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
            ),
            child: Center(
              child: showBusyIndicator
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: AppCircularProgressIndicator(
                        color: enabled
                            ? widget.theme.secondary
                            : widget.theme.textSecondary,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(
                      iconData,
                      size: 16,
                      color: enabled
                          ? (_isHovered
                                ? activeColor
                                : activeColor.withValues(alpha: 0.9))
                          : (_isHovered
                                ? widget.theme.accent
                                : widget.theme.textSecondary),
                    ),
            ),
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

/// Transparent overlay that adds resize handles at window edges on Linux.
///
/// `TitleBarStyle.hidden` removes the GTK window decorations that normally
/// provide resize borders. This widget restores that behaviour by placing
/// thin [MouseRegion] + [GestureDetector] strips at all four edges and four
/// corners, and calling [windowManager.startResizing] on pointer-down.
class _LinuxResizeFrame extends StatelessWidget {
  const _LinuxResizeFrame();

  static const double _edge = 6.0;
  static const double _corner = 12.0;

  Widget _handle(ResizeEdge edge, MouseCursor cursor) => MouseRegion(
    cursor: cursor,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startResizing(edge),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Edges ──────────────────────────────────────────────────────────
        // Left
        Positioned(
          left: 0,
          top: _corner,
          bottom: _corner,
          width: _edge,
          child: _handle(ResizeEdge.left, SystemMouseCursors.resizeLeftRight),
        ),
        // Right
        Positioned(
          right: 0,
          top: _corner,
          bottom: _corner,
          width: _edge,
          child: _handle(ResizeEdge.right, SystemMouseCursors.resizeLeftRight),
        ),
        // Top
        Positioned(
          top: 0,
          left: _corner,
          right: _corner,
          height: _edge,
          child: _handle(ResizeEdge.top, SystemMouseCursors.resizeUpDown),
        ),
        // Bottom
        Positioned(
          bottom: 0,
          left: _corner,
          right: _corner,
          height: _edge,
          child: _handle(ResizeEdge.bottom, SystemMouseCursors.resizeUpDown),
        ),
        // ── Corners ────────────────────────────────────────────────────────
        // Top-left
        Positioned(
          top: 0,
          left: 0,
          width: _corner,
          height: _corner,
          child: _handle(
            ResizeEdge.topLeft,
            SystemMouseCursors.resizeUpLeftDownRight,
          ),
        ),
        // Top-right
        Positioned(
          top: 0,
          right: 0,
          width: _corner,
          height: _corner,
          child: _handle(
            ResizeEdge.topRight,
            SystemMouseCursors.resizeUpRightDownLeft,
          ),
        ),
        // Bottom-left
        Positioned(
          bottom: 0,
          left: 0,
          width: _corner,
          height: _corner,
          child: _handle(
            ResizeEdge.bottomLeft,
            SystemMouseCursors.resizeUpRightDownLeft,
          ),
        ),
        // Bottom-right
        Positioned(
          bottom: 0,
          right: 0,
          width: _corner,
          height: _corner,
          child: _handle(
            ResizeEdge.bottomRight,
            SystemMouseCursors.resizeUpLeftDownRight,
          ),
        ),
      ],
    );
  }
}
