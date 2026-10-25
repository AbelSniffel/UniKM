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
import '../core/services/deadline_notification_service.dart';
import '../core/services/logging.dart';
import '../core/services/update_service.dart';
import '../core/settings/settings_model.dart';
import '../core/theme/app_theme.dart';
import '../providers/app_providers.dart';
import '../core/models/device_sync_models.dart';
import 'dialogs/incoming_pair_dialog.dart';
import 'dialogs/dialog_gallery.dart' show DialogGalleryHost;
import 'pages/add_games_page.dart';
import 'pages/home_page.dart';
import 'pages/home_sections/selection_ribbon_host.dart';
import 'pages/settings_page.dart';
import 'pages/update_page.dart';
import 'widgets/navigation_panel.dart' as nav_panel;
import 'widgets/app_progress_indicator.dart';
import 'widgets/app_page_stack.dart';
import 'widgets/dev_window.dart';
import 'widgets/app_title_bar.dart';
import 'widgets/dialog_helpers.dart';
import 'widgets/notification_system.dart';
import 'widgets/sync_progress_notifications.dart';

const int _kLargeLibraryNavAnimationThreshold = 250;

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
  Size? _lastViewportSize;
  bool _navSelectionTransitionActive = false;
  Timer? _navSelectionAnimTimer;
  final Set<String> _handledPairRequestPrompts = <String>{};
  final _syncProgressNotifications = SyncProgressNotifications();
  StreamSubscription<SyncEvent>? _syncProgressSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _syncProgressSub = ref
        .read(deviceSyncServiceProvider)
        .syncEvents
        .listen(_syncProgressNotifications.handle);
    _applyMobileSystemUiMode();
    _initWindow();
    _initAutoBackup();
    _initAutoUpdateChecks();
  }

  @override
  void dispose() {
    _cancelAllTimers();
    _syncProgressSub?.cancel();
    _syncProgressNotifications.dispose();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  void _cancelAllTimers() {
    for (final timer in [
      _windowSaveDebounce,
      _autoBackupTimer,
      _autoUpdateTimer,
      _navSelectionAnimTimer,
    ]) {
      timer?.cancel();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyMobileSystemUiMode();
      unawaited(ref.read(deviceSyncProvider.notifier).setForeground(true));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(deviceSyncProvider.notifier).setForeground(false));
    }
  }

  void _applyMobileSystemUiMode() {
    if (!Platform.isAndroid) return;
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
    final intervalMinutes = shellSettings.autoBackupIntervalMinutes;
    void setNextBackup(DateTime? time) =>
        ref.read(nextAutoBackupTimeProvider.notifier).set(time);
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;

    if (!shellSettings.autoBackupEnabled || intervalMinutes <= 0) {
      setNextBackup(null);
      return;
    }
    final interval = Duration(minutes: intervalMinutes);
    setNextBackup(DateTime.now().add(interval));
    _autoBackupTimer = Timer.periodic(interval, (_) async {
      if (!mounted) return;
      setNextBackup(DateTime.now().add(interval));
      // Auto backups stay silent; developer mode reports successes.
      try {
        final result = await ref.read(backupServiceProvider).createBackup();
        if (result.success &&
            ref.read(appShellSettingsProvider).developerMode) {
          NotificationManager.instance.info(
            'Auto backup created: ${result.backupInfo?.displayName}',
          );
        }
      } catch (e) {
        AppLog.w('Auto backup failed', error: e);
      }
    });
  }

  void _scheduleNextAutoUpdateCheck({bool useStartupDelay = false}) {
    _autoUpdateTimer?.cancel();
    _autoUpdateTimer = null;
    if (!ref.read(updatesSettingsProvider).autoCheckEnabled) {
      ref.read(nextAutoUpdateTimeProvider.notifier).set(null);
      return;
    }

    final delay = useStartupDelay
        ? const Duration(seconds: 3)
        : const Duration(minutes: kDefaultAutoUpdateIntervalMinutes);

    ref
        .read(nextAutoUpdateTimeProvider.notifier)
        .set(DateTime.now().add(delay));

    _autoUpdateTimer = Timer(delay, () async {
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

    if (!ref.read(desktopWindowSessionProvider).claimInitialization()) {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _windowMaximized = maximized);
      return;
    }

    await windowManager.ensureInitialized();
    // Prevent immediate close so we can persist encrypted DB changes.
    await windowManager.setPreventClose(true);

    _applyingSavedWindowState = true;
    final settings = ref.read(appShellSettingsProvider);

    // Always use the primary display to avoid off-screen launches.
    final hasSaved = settings.windowX != null && settings.windowY != null;
    final targetDisplay = await screenRetriever.getPrimaryDisplay();
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
      title: kAppName,
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

    // Best effort only: Windows briefly pins the window on top to take focus.
    Future<void> refocus({bool? alwaysOnTop}) async {
      try {
        if (alwaysOnTop != null) {
          await windowManager.setAlwaysOnTop(alwaysOnTop);
        }
        await windowManager.focus();
      } catch (_) {}
    }

    final isWindows = Platform.isWindows;
    if (isWindows) await refocus(alwaysOnTop: true);
    unawaited(
      Future<void>.delayed(
        Duration(milliseconds: isWindows ? 160 : 80),
        () async {
          if (mounted) await refocus(alwaysOnTop: isWindows ? false : null);
        },
      ),
    );
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
        for (final (key, value) in <(String, Object)>[
          (SettingsKeys.windowWidth, size.width),
          (SettingsKeys.windowHeight, size.height),
          (SettingsKeys.windowX, pos.dx),
          (SettingsKeys.windowY, pos.dy),
          (SettingsKeys.windowMaximized, maximized),
        ]) {
          await settingsNotifier.setSetting(key, value);
        }
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
  void onWindowMaximize() => _onMaximizedChanged(true);

  @override
  void onWindowUnmaximize() => _onMaximizedChanged(false);

  void _onMaximizedChanged(bool maximized) {
    _scheduleSaveWindowState();
    if (mounted && Platform.isLinux) {
      setState(() => _windowMaximized = maximized);
    }
  }

  Future<void> _cleanupOnClose() async {
    final session = ref.read(encryptedDbSessionProvider);
    if (session == null) {
      try {
        await ref.read(requireDatabaseProvider).close();
      } catch (e) {
        // Ignore close errors on shutdown, but log for debugging
        AppLog.d('Database close on shutdown failed: $e');
      }
      return;
    }
    try {
      NotificationManager.instance.info('Saving encrypted database…');
      await session.closeAndPersist(ref.read(requireDatabaseProvider));
    } catch (e) {
      // Avoid trapping the user in a close loop.
      NotificationManager.instance.error(
        'Failed to save encrypted database: $e',
      );
    }
  }

  @override
  void onWindowClose() async {
    if (_isClosingWindow || !await windowManager.isPreventClose()) return;
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
    void updateReminderSchedule() {
      unawaited(
        DeadlineNotificationService.instance
            .updateSchedule(
              ref.read(allGamesProvider),
              enabled: ref
                  .read(notificationsSettingsProvider)
                  .deadlineReminders,
            )
            .catchError(
              (Object error) =>
                  AppLog.w('Could not schedule deadline reminders: $error'),
            ),
      );
    }

    ref.listen(allGamesProvider, (_, _) => updateReminderSchedule());
    ref.listen(
      notificationsSettingsProvider,
      (_, _) => updateReminderSchedule(),
    );
    final theme = ref.watch(themeProvider);
    final currentNav = ref.watch(currentNavProvider);
    final hasSelectedGames = ref.watch(
      gamesProvider.select((s) => s.selectedGameIds.isNotEmpty),
    );
    final showSelectionRibbon = currentNav == NavItem.home && hasSelectedGames;
    final shellSettings = ref.watch(appShellSettingsProvider);
    final hideNavForSelection =
        showSelectionRibbon &&
        shellSettings.navBarPosition == NavBarPosition.bottom;
    final databaseRevision = ref.watch(
      databaseNotifierProvider.select((state) => state.revision),
    );
    final viewportSize = MediaQuery.sizeOf(context);
    final viewportChanged =
        _lastViewportSize != null && _lastViewportSize != viewportSize;
    _lastViewportSize = viewportSize;
    final viewportWidth = viewportSize.width;

    ref.listen<UpdatesSettings>(updatesSettingsProvider, (previous, next) {
      if (previous != null &&
          previous.autoCheckEnabled != next.autoCheckEnabled) {
        _scheduleNextAutoUpdateCheck();
      }
    });

    ref.listen<bool>(
      gamesProvider.select((s) => s.selectedGameIds.isNotEmpty),
      (previous, next) {
        if (previous == null || previous == next) return;
        if (!next) {
          ref.read(selectionMultiSelectModeProvider.notifier).setEnabled(false);
        }
        setState(() => _navSelectionTransitionActive = true);
        _navSelectionAnimTimer?.cancel();
        _navSelectionAnimTimer = Timer(kNavPanelMotionAnimation, () {
          if (mounted) setState(() => _navSelectionTransitionActive = false);
        });
      },
    );

    // Prompt for one new incoming pair request at a time.
    ref.listen(deviceSyncProvider, (previous, next) {
      final pending = next.asData?.value.pendingPairRequests;
      if (pending == null) return;
      final activeIds = {for (final r in pending) r.requestId};
      _handledPairRequestPrompts.retainWhere(activeIds.contains);
      final request = pending
          .where((r) => !_handledPairRequestPrompts.contains(r.requestId))
          .firstOrNull;
      if (request == null) return;
      _handledPairRequestPrompts.add(request.requestId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final stillPending =
            ref
                .read(deviceSyncProvider)
                .asData
                ?.value
                .pendingPairRequests
                .any((r) => r.requestId == request.requestId) ??
            false;
        if (stillPending) {
          _showIncomingPairRequestPrompt(context, request);
        } else {
          _handledPairRequestPrompts.remove(request.requestId);
        }
      });
    });

    final navPosition = shellSettings.navBarPosition;
    final navAppearance = shellSettings.navBarAppearance;
    final gradientAnimation = shellSettings.gradientAnimation;
    // Measure against the width the selected button needs when expanded.
    // Using the current collapsed width would shift the breakpoint on resize.
    final baseNavCollapsed = navAppearance == NavBarAppearance.iconOnly;
    final isVeryNarrowLayout = nav_panel.isVeryNarrowAppLayout(
      viewportWidth,
      position: navPosition,
      appearance: navAppearance,
    );
    final forceCollapsedNav = isVeryNarrowLayout;
    final navCollapsed =
        baseNavCollapsed ||
        shellSettings.navExpansionMode == NavExpansionMode.collapsed ||
        forceCollapsedNav;
    final filteredGameCount = currentNav == NavItem.home
        ? ref.watch(gamesProvider.select((s) => s.filteredGames.length))
        : 0;
    final skipNavSizeAnimationForLargeLibrary =
        !_navSelectionTransitionActive &&
        !hideNavForSelection &&
        currentNav == NavItem.home &&
        filteredGameCount >= _kLargeLibraryNavAnimationThreshold;
    final navPositionChanged =
        _lastNavPosition != null && _lastNavPosition != navPosition;
    _lastNavPosition = navPosition;
    // Native window dragging already supplies continuous sizes. Do not chase
    // those sizes with a second layout animation on any page.
    final navMotionAnimationDuration =
        viewportChanged || skipNavSizeAnimationForLargeLibrary
        ? Duration.zero
        : kNavPanelMotionAnimation;

    // Keep the expanded vertical rail compact while preserving button spacing.
    final navWidth = navCollapsed
        ? nav_panel.kNavigationPanelCollapsedWidth
        : nav_panel.kNavigationPanelExpandedWidth;
    const navPanelHorizontalExtent = nav_panel.kNavigationPanelHorizontalExtent;

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
              hasNotification: hasNotification,
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
            tooltipLabel: item == NavItem.addGames ? 'Add Games' : null,
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
      ref.read(currentNavProvider.notifier).set(targetNav);
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
      isVeryNarrowLayout,
    );

    Widget buildNavSlot(NavBarPosition position) {
      final isVertical =
          position == NavBarPosition.left || position == NavBarPosition.right;
      final panel = buildNavPanel(position);
      // Each slot spans the edge it is docked to.
      return Positioned(
        left: position == NavBarPosition.right ? null : 0,
        right: position == NavBarPosition.left ? null : 0,
        top: position == NavBarPosition.bottom ? null : 0,
        bottom: position == NavBarPosition.top ? null : 0,
        height: isVertical ? null : navPanelHorizontalExtent,
        child: _NavPositionSlot(
          key: ValueKey('nav-slot-${position.name}'),
          position: position,
          isActive: navPosition == position && !hideNavForSelection,
          child: isVertical
              ? AnimatedContainer(
                  duration: navMotionAnimationDuration,
                  curve: kNavPanelMotionCurve,
                  width: navWidth,
                  child: panel,
                )
              : panel,
        ),
      );
    }

    final navLayoutAnimationDuration = viewportChanged
        ? Duration.zero
        : navPositionChanged
        ? kNavPanelMotionAnimation
        : navMotionAnimationDuration;
    final pageInsets = hideNavForSelection
        ? EdgeInsets.zero
        : switch (navPosition) {
            NavBarPosition.left => EdgeInsets.only(left: navWidth),
            NavBarPosition.right => EdgeInsets.only(right: navWidth),
            NavBarPosition.top => EdgeInsets.only(
              top: navPanelHorizontalExtent,
            ),
            NavBarPosition.bottom => EdgeInsets.only(
              bottom: navPanelHorizontalExtent,
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
                if (_hasDesktopWindowControls) ...[AppTitleBar(theme: theme)],

                // Main content with configurable navigation
                Expanded(
                  child: DialogGalleryHost(
                    child: ClipRect(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedPadding(
                              key: const ValueKey('page-navigation-insets'),
                              duration: navLayoutAnimationDuration,
                              curve: kNavPanelMotionCurve,
                              padding: pageInsets,
                              child: SelectionRibbonHost(
                                visible: showSelectionRibbon,
                                atTop: false,
                                isVeryNarrowLayout: isVeryNarrowLayout,
                                child: pagesStack,
                              ),
                            ),
                          ),
                          ...NavBarPosition.values.map(buildNavSlot),
                        ],
                      ),
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
    bool isVeryNarrowLayout,
  ) {
    return AppPageStack(
      key: ValueKey(databaseRevision),
      index: currentNav.index,
      children: [
        // Const page configurations keep unrelated shell rebuilds from
        // rebuilding the retained page trees. Providers still update normally.
        if (isVeryNarrowLayout)
          const HomePage(isVeryNarrowLayout: true)
        else
          const HomePage(),
        const AddGamesPage(),
        const UpdatePage(),
        const SettingsPage(),
      ],
    );
  }

  Future<void> _showIncomingPairRequestPrompt(
    BuildContext context,
    PendingPairRequest request,
  ) async {
    if (!context.mounted) return;
    final result = await showAppDialog<IncomingPairDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => IncomingPairDialog(request: request),
    );
    if (!context.mounted || result != null) return;

    // Manual dismiss (Esc / window close button) returns null.
    // Treat that as an explicit decline so the initiator isn't left waiting
    // for request timeout.
    try {
      await ref
          .read(deviceSyncProvider.notifier)
          .respondToPairRequest(requestId: request.requestId, accept: false);
    } catch (_) {
      // Request may already be resolved remotely.
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
  Widget build(BuildContext context) => SizedBox.square(
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

  @override
  Widget build(BuildContext context) {
    final startOffset = switch (position) {
      NavBarPosition.left => const Offset(-1, 0),
      NavBarPosition.right => const Offset(1, 0),
      NavBarPosition.top => const Offset(0, -1),
      NavBarPosition.bottom => const Offset(0, 1),
    };
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        return FractionalTranslation(
          translation: startOffset * (1 - t),
          child: Opacity(opacity: 0.68 + (0.32 * t), child: child!),
        );
      },
    );
  }
}

/// Test harness for the shared title bar without constructing the full shell.
Widget buildTitleBarForTest(AppThemeData theme) =>
    Material(child: AppTitleBar(theme: theme));

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

  // Edges first, then corners. Edges stop short of the corner squares.
  static const _edges = [
    ResizeEdge.left,
    ResizeEdge.right,
    ResizeEdge.top,
    ResizeEdge.bottom,
    ResizeEdge.topLeft,
    ResizeEdge.topRight,
    ResizeEdge.bottomLeft,
    ResizeEdge.bottomRight,
  ];

  Widget _handle(ResizeEdge edge) {
    final name = edge.name.toLowerCase();
    final left = name.contains('left'), right = name.contains('right');
    final top = name.startsWith('top'), bottom = name.startsWith('bottom');
    final horizontal = left || right, vertical = top || bottom;
    final corner = horizontal && vertical;
    return Positioned(
      left: right ? null : (left ? 0 : _corner),
      right: left ? null : (right ? 0 : _corner),
      top: bottom ? null : (top ? 0 : _corner),
      bottom: top ? null : (bottom ? 0 : _corner),
      width: corner ? _corner : (horizontal ? _edge : null),
      height: corner ? _corner : (vertical ? _edge : null),
      child: MouseRegion(
        cursor: !corner
            ? (horizontal
                  ? SystemMouseCursors.resizeLeftRight
                  : SystemMouseCursors.resizeUpDown)
            : left == top
            ? SystemMouseCursors.resizeUpLeftDownRight
            : SystemMouseCursors.resizeUpRightDownLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => windowManager.startResizing(edge),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      Stack(children: [for (final edge in _edges) _handle(edge)]);
}
