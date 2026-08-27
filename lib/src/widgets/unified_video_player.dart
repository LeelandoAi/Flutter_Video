import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controller.dart';
import '../kernel.dart';
import '../models.dart';
import 'player_view/player_controls.dart';
import 'player_view/player_episode_panel.dart';
import 'player_view/player_settings_panel.dart';
import 'player_view/player_state_overlay.dart';
import 'player_view/player_view_tokens.dart';

class UnifiedVideoPlayer extends StatefulWidget {
  const UnifiedVideoPlayer({
    super.key,
    required this.controller,
    this.episodes = const <VideoEpisode>[],
    this.initialEpisodeId,
    this.onEpisodeChanged,
    this.onPrevious,
    this.onNext,
    this.onSwitchContent,
    this.aspectRatio = 16 / 9,
    this.autoHideControlsDelay = const Duration(seconds: 3),
  });

  final UnifiedVideoController controller;
  final List<VideoEpisode> episodes;
  final String? initialEpisodeId;
  final ValueChanged<VideoEpisode>? onEpisodeChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSwitchContent;
  final double aspectRatio;
  final Duration autoHideControlsDelay;

  @override
  State<UnifiedVideoPlayer> createState() => _UnifiedVideoPlayerState();
}

class _UnifiedVideoPlayerState extends State<UnifiedVideoPlayer> {
  final OverlayPortalController _fullscreenPortal = OverlayPortalController();
  final GlobalKey _playerViewKey = GlobalKey(
    debugLabel: 'unified-video-player-view',
  );
  bool _fullscreenOverlayVisible = false;
  bool _fullscreenTransitioning = false;
  String? _activeEpisodeId;
  String? _openingEpisodeId;
  int _episodeOperationGeneration = 0;
  VideoSource? _openingEpisodeSource;
  VideoSource? _quarantinedInternalSource;
  bool _quarantinedInternalOperationPending = false;
  int? _quarantinedInternalOperationGeneration;
  VideoSource? _lastObservedSource;
  UnifiedVideoLifecycle? _lastObservedLifecycle;

  @override
  void initState() {
    super.initState();
    _validateEpisodes(widget.episodes);
    _lastObservedSource = widget.controller.value.source;
    _lastObservedLifecycle = widget.controller.value.lifecycle;
    _activeEpisodeId =
        _episodeWithId(widget.initialEpisodeId)?.id ??
        _episodeMatchingSource(widget.controller.value.source)?.id;
    widget.controller.claimFullscreenOwnershipIfUnclaimed();
    widget.controller.addListener(_handleControllerFullscreenChanged);
  }

  @override
  void didUpdateWidget(covariant UnifiedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateEpisodes(widget.episodes);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerFullscreenChanged);
      oldWidget.controller.releaseFullscreenOwnership();
      widget.controller.claimFullscreenOwnershipIfUnclaimed();
      widget.controller.addListener(_handleControllerFullscreenChanged);
      _episodeOperationGeneration += 1;
      _openingEpisodeId = null;
      _openingEpisodeSource = null;
      _quarantinedInternalSource = null;
      _quarantinedInternalOperationPending = false;
      _quarantinedInternalOperationGeneration = null;
      _lastObservedSource = widget.controller.value.source;
      _lastObservedLifecycle = widget.controller.value.lifecycle;
      _syncActiveEpisodeFromSource();
    } else if (oldWidget.episodes != widget.episodes) {
      if (_openingEpisodeId != null) {
        final int invalidatedGeneration = _episodeOperationGeneration;
        _episodeOperationGeneration += 1;
        _quarantinedInternalSource = _openingEpisodeSource;
        _quarantinedInternalOperationPending = true;
        _quarantinedInternalOperationGeneration = invalidatedGeneration;
        _openingEpisodeId = null;
        _openingEpisodeSource = null;
      }
      if (_episodeWithId(_activeEpisodeId) == null) {
        _syncActiveEpisodeFromSource();
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerFullscreenChanged);
    widget.controller.releaseFullscreenOwnership();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_fullscreenOverlayVisible,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _fullscreenOverlayVisible) {
          _ignorePlaybackError(_toggleFullscreen);
        }
      },
      child: OverlayPortal(
        controller: _fullscreenPortal,
        overlayChildBuilder: (BuildContext context) {
          return Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: _buildPlayerView(expand: true),
            ),
          );
        },
        child: _fullscreenOverlayVisible
            ? AspectRatio(
                aspectRatio: widget.aspectRatio,
                child: const ColoredBox(color: Colors.black),
              )
            : _buildPlayerView(),
      ),
    );
  }

  Widget _buildPlayerView({bool expand = false}) {
    final Widget playerView = _UnifiedVideoPlayerView(
      key: _playerViewKey,
      controller: widget.controller,
      episodes: widget.episodes,
      activeEpisodeId: _activeEpisodeId,
      openingEpisodeId: _openingEpisodeId,
      onEpisodeSelected: _openEpisode,
      onPrevious: _previousEpisodeAction(),
      onNext: _nextEpisodeAction(),
      onSwitchContent: widget.onSwitchContent,
      onFullscreenPressed: _toggleFullscreen,
      autoHideControlsDelay: widget.autoHideControlsDelay,
    );
    if (expand) {
      return SizedBox.expand(child: playerView);
    }
    return ValueListenableBuilder<UnifiedVideoState>(
      valueListenable: widget.controller,
      builder: (BuildContext context, UnifiedVideoState state, Widget? child) {
        return AspectRatio(
          aspectRatio: _playerAspectRatio(widget.aspectRatio, state.fit),
          child: child,
        );
      },
      child: playerView,
    );
  }

  void _handleControllerFullscreenChanged() {
    if (!mounted) {
      return;
    }
    final UnifiedVideoState state = widget.controller.value;
    final UnifiedVideoLifecycle? previousLifecycle = _lastObservedLifecycle;
    _lastObservedLifecycle = state.lifecycle;
    final VideoSource? source = state.source;
    if (!_sameSource(source, _lastObservedSource)) {
      if (_openingEpisodeId == null) {
        final bool sourceIsQuarantined = _sameSource(
          source,
          _quarantinedInternalSource,
        );
        final bool completedExternalOpen =
            sourceIsQuarantined &&
            !_quarantinedInternalOperationPending &&
            previousLifecycle == UnifiedVideoLifecycle.opening &&
            state.lifecycle == UnifiedVideoLifecycle.ready;
        if (!sourceIsQuarantined || completedExternalOpen) {
          if (completedExternalOpen) {
            _quarantinedInternalSource = null;
            _quarantinedInternalOperationGeneration = null;
          }
          _lastObservedSource = source;
          _syncActiveEpisodeFromSource();
        }
      }
    }
    if (_fullscreenTransitioning) {
      return;
    }
    final bool fullscreen = widget.controller.value.fullscreen;
    if (fullscreen == _fullscreenOverlayVisible) {
      return;
    }
    if (fullscreen) {
      setState(() => _fullscreenOverlayVisible = true);
      _fullscreenPortal.show();
    } else {
      _fullscreenPortal.hide();
      setState(() => _fullscreenOverlayVisible = false);
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_fullscreenTransitioning) {
      return;
    }
    _fullscreenTransitioning = true;
    try {
      if (_fullscreenOverlayVisible || widget.controller.value.fullscreen) {
        await _exitFullscreen();
      } else {
        await _enterFullscreen();
      }
    } finally {
      _fullscreenTransitioning = false;
    }
  }

  Future<void> _enterFullscreen() async {
    await widget.controller.enterFullscreen(syncPlatform: false);
    if (!mounted) {
      return;
    }
    setState(() => _fullscreenOverlayVisible = true);
    _fullscreenPortal.show();
    await WidgetsBinding.instance.endOfFrame;
    try {
      await widget.controller.syncFullscreenPlatform();
    } catch (_) {
      await widget.controller.exitFullscreen(syncPlatform: false);
      if (mounted) {
        _fullscreenPortal.hide();
        setState(() => _fullscreenOverlayVisible = false);
      }
      rethrow;
    }
  }

  Future<void> _exitFullscreen() async {
    await widget.controller.exitFullscreen(syncPlatform: false);
    try {
      await widget.controller.syncFullscreenPlatform();
    } catch (_) {
      await widget.controller.enterFullscreen(syncPlatform: false);
      rethrow;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    _fullscreenPortal.hide();
    setState(() => _fullscreenOverlayVisible = false);
  }

  void _validateEpisodes(List<VideoEpisode> episodes) {
    final Set<String> ids = <String>{};
    for (final VideoEpisode episode in episodes) {
      if (episode.id.trim().isEmpty || !ids.add(episode.id)) {
        throw FlutterError('VideoEpisode.id 必须非空且在同一列表中唯一。');
      }
      if (episode.title.trim().isEmpty) {
        throw FlutterError('VideoEpisode.title 必须非空。');
      }
    }
  }

  VideoEpisode? _episodeWithId(String? id) {
    if (id == null) {
      return null;
    }
    for (final VideoEpisode episode in widget.episodes) {
      if (episode.id == id) {
        return episode;
      }
    }
    return null;
  }

  VideoEpisode? _episodeMatchingSource(VideoSource? source) {
    if (source == null) {
      return null;
    }
    for (final VideoEpisode episode in widget.episodes) {
      if (_sameSource(episode.source, source)) {
        return episode;
      }
    }
    return null;
  }

  bool _sameSource(VideoSource? first, VideoSource? second) {
    return first?.type == second?.type && first?.uri == second?.uri;
  }

  void _syncActiveEpisodeFromSource() {
    final String? matchedId = _episodeMatchingSource(
      widget.controller.value.source,
    )?.id;
    if (matchedId == _activeEpisodeId) {
      return;
    }
    if (mounted) {
      setState(() => _activeEpisodeId = matchedId);
    } else {
      _activeEpisodeId = matchedId;
    }
  }

  VoidCallback? _previousEpisodeAction() =>
      _episodeAction(offset: -1, legacyCallback: widget.onPrevious);

  VoidCallback? _nextEpisodeAction() =>
      _episodeAction(offset: 1, legacyCallback: widget.onNext);

  VoidCallback? _episodeAction({
    required int offset,
    required VoidCallback? legacyCallback,
  }) {
    if (widget.episodes.isEmpty) {
      return legacyCallback;
    }
    if (_openingEpisodeId != null) {
      return null;
    }
    final int activeIndex = widget.episodes.indexWhere(
      (VideoEpisode episode) => episode.id == _activeEpisodeId,
    );
    if (activeIndex == -1) {
      return legacyCallback;
    }
    final int targetIndex = activeIndex + offset;
    if (targetIndex < 0 || targetIndex >= widget.episodes.length) {
      return null;
    }
    return () => _ignorePlaybackError(() async {
      await _openEpisode(widget.episodes[targetIndex]);
    });
  }

  Future<bool> _openEpisode(VideoEpisode episode) async {
    if (_openingEpisodeId != null || episode.id == _activeEpisodeId) {
      return false;
    }
    final UnifiedVideoController openingController = widget.controller;
    final int openingGeneration = ++_episodeOperationGeneration;
    setState(() {
      _openingEpisodeId = episode.id;
      _openingEpisodeSource = episode.source;
    });
    try {
      await openingController.open(episode.source);
      if (!mounted ||
          widget.controller != openingController ||
          _episodeOperationGeneration != openingGeneration) {
        return false;
      }
      setState(() {
        _activeEpisodeId = episode.id;
        _lastObservedSource = openingController.value.source;
        _quarantinedInternalSource = null;
        _quarantinedInternalOperationPending = false;
        _quarantinedInternalOperationGeneration = null;
      });
      widget.onEpisodeChanged?.call(episode);
      return true;
    } catch (_) {
      if (mounted &&
          widget.controller == openingController &&
          _episodeOperationGeneration == openingGeneration) {
        _quarantinedInternalSource = episode.source;
        _quarantinedInternalOperationPending = false;
        _quarantinedInternalOperationGeneration = openingGeneration;
      }
      rethrow;
    } finally {
      if (mounted &&
          _quarantinedInternalOperationGeneration == openingGeneration &&
          _episodeOperationGeneration != openingGeneration &&
          _sameSource(_quarantinedInternalSource, episode.source)) {
        _quarantinedInternalOperationPending = false;
      }
      if (mounted &&
          widget.controller == openingController &&
          _episodeOperationGeneration == openingGeneration &&
          _openingEpisodeId == episode.id) {
        setState(() {
          _openingEpisodeId = null;
          _openingEpisodeSource = null;
        });
      }
    }
  }
}

class _UnifiedVideoPlayerView extends StatefulWidget {
  const _UnifiedVideoPlayerView({
    super.key,
    required this.controller,
    required this.episodes,
    required this.activeEpisodeId,
    required this.openingEpisodeId,
    required this.onEpisodeSelected,
    required this.onPrevious,
    required this.onNext,
    required this.onSwitchContent,
    required this.onFullscreenPressed,
    required this.autoHideControlsDelay,
  });

  final UnifiedVideoController controller;
  final List<VideoEpisode> episodes;
  final String? activeEpisodeId;
  final String? openingEpisodeId;
  final Future<bool> Function(VideoEpisode episode) onEpisodeSelected;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSwitchContent;
  final Future<void> Function() onFullscreenPressed;
  final Duration autoHideControlsDelay;

  @override
  State<_UnifiedVideoPlayerView> createState() =>
      _UnifiedVideoPlayerViewState();
}

enum _PlayerContextOverlay { episode, speed, settings }

class _UnifiedVideoPlayerViewState extends State<_UnifiedVideoPlayerView>
    with SingleTickerProviderStateMixin {
  bool _controlsVisible = true;
  _PlayerContextOverlay? _contextOverlay;
  bool _contextOverlayInteractive = false;
  bool _scrubbing = false;
  bool _danmakuEnabled = false;
  bool _mirrored = false;
  bool _nightModeEnabled = false;
  int _quarterTurns = 0;
  int _contextOverlayGeneration = 0;
  Timer? _hideControlsTimer;
  UnifiedVideoLifecycle? _lastLifecycle;
  late bool _lastFullscreen;
  late final AnimationController _contextPanelController;
  late final Animation<double> _contextPanelAnimation;

  @override
  void initState() {
    super.initState();
    _lastLifecycle = widget.controller.value.lifecycle;
    _lastFullscreen = widget.controller.value.fullscreen;
    _contextPanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _contextPanelAnimation = CurvedAnimation(
      parent: _contextPanelController,
      curve: const Cubic(0.32, 0.72, 0, 1),
      reverseCurve: Curves.easeInQuart,
    );
    widget.controller.addListener(_handlePlaybackStateChanged);
    _scheduleAutoHideIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _UnifiedVideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handlePlaybackStateChanged);
      widget.controller.addListener(_handlePlaybackStateChanged);
      _controlsVisible = true;
      _scrubbing = false;
      _lastLifecycle = widget.controller.value.lifecycle;
      _lastFullscreen = widget.controller.value.fullscreen;
      _closeContextOverlay();
      _scheduleAutoHideIfNeeded();
    } else if (widget.episodes.isEmpty &&
        oldWidget.episodes.isNotEmpty &&
        _contextOverlay == _PlayerContextOverlay.episode) {
      _closeContextOverlay();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handlePlaybackStateChanged);
    _hideControlsTimer?.cancel();
    _contextPanelController.dispose();
    super.dispose();
  }

  void _handlePlaybackStateChanged() {
    final UnifiedVideoState state = widget.controller.value;
    final UnifiedVideoLifecycle? previousLifecycle = _lastLifecycle;
    final bool lifecycleChanged = state.lifecycle != previousLifecycle;
    final bool reachedEnded =
        state.lifecycle == UnifiedVideoLifecycle.ended &&
        previousLifecycle != UnifiedVideoLifecycle.ended;
    _lastLifecycle = state.lifecycle;
    if (_lastFullscreen && !state.fullscreen) {
      _closeContextOverlay();
    }
    _lastFullscreen = state.fullscreen;
    if (reachedEnded && mounted && !_controlsVisible) {
      setState(() => _controlsVisible = true);
      _scheduleAutoHideIfNeeded();
      return;
    }
    if (!_canAutoHide(state)) {
      _hideControlsTimer?.cancel();
      if (mounted && !_controlsVisible) {
        setState(() => _controlsVisible = true);
      }
      return;
    }
    if (lifecycleChanged && _controlsVisible) {
      _scheduleAutoHideIfNeeded();
    }
  }

  void _toggleControls() {
    _showControls();
  }

  void _showControls() {
    widget.controller.claimFullscreenOwnership();
    if (mounted && !_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _scheduleAutoHideIfNeeded();
  }

  void _hideControlsNow() {
    _hideControlsTimer?.cancel();
    if (mounted && _controlsVisible && _canAutoHide(widget.controller.value)) {
      setState(() => _controlsVisible = false);
    }
  }

  void _scheduleAutoHideIfNeeded() {
    _hideControlsTimer?.cancel();
    if (!_canAutoHide(widget.controller.value)) {
      return;
    }
    _hideControlsTimer = Timer(widget.autoHideControlsDelay, _hideControlsNow);
  }

  bool get _reduceMotion {
    final bool platformReduceMotion = View.of(
      context,
    ).platformDispatcher.accessibilityFeatures.reduceMotion;
    return MediaQuery.disableAnimationsOf(context) || platformReduceMotion;
  }

  void _configureContextPanelMotion() {
    final Duration enter = Duration(milliseconds: _reduceMotion ? 200 : 400);
    final Duration exit = Duration(milliseconds: _reduceMotion ? 200 : 260);
    _contextPanelController
      ..duration = enter
      ..reverseDuration = exit;
  }

  void _toggleContextOverlay(_PlayerContextOverlay overlay) {
    if (_contextOverlay == overlay && _contextOverlayInteractive) {
      _closeContextOverlay();
    } else {
      unawaited(_openContextOverlay(overlay));
    }
  }

  Future<void> _openContextOverlay(_PlayerContextOverlay overlay) async {
    final int generation = ++_contextOverlayGeneration;
    _hideControlsTimer?.cancel();
    _configureContextPanelMotion();
    if (_contextOverlay != null && !_contextPanelController.isDismissed) {
      if (mounted) {
        setState(() => _contextOverlayInteractive = false);
      }
      try {
        await _contextPanelController.reverse().orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || generation != _contextOverlayGeneration) {
      return;
    }
    setState(() {
      _contextOverlay = overlay;
      _contextOverlayInteractive = true;
    });
    _contextPanelController.forward(from: 0);
  }

  void _closeContextOverlay() {
    final int generation = ++_contextOverlayGeneration;
    unawaited(_dismissContextOverlay(generation));
  }

  Future<void> _dismissContextOverlay(int generation) async {
    if (_contextOverlay == null && _contextPanelController.isDismissed) {
      return;
    }
    _configureContextPanelMotion();
    if (mounted) {
      setState(() => _contextOverlayInteractive = false);
    } else {
      _contextOverlayInteractive = false;
    }
    try {
      await _contextPanelController.reverse().orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || generation != _contextOverlayGeneration) {
      return;
    }
    setState(() => _contextOverlay = null);
    _scheduleAutoHideIfNeeded();
  }

  Future<void> _selectEpisode(VideoEpisode episode) async {
    try {
      final bool opened = await widget.onEpisodeSelected(episode);
      if (opened &&
          mounted &&
          _contextOverlay == _PlayerContextOverlay.episode) {
        _closeContextOverlay();
      }
    } catch (_) {
      // The controller exposes the failed state; keep the picker available.
    }
  }

  Future<void> _selectSpeed(double speed) async {
    final int generation = _contextOverlayGeneration;
    try {
      await widget.controller.setSpeed(speed);
    } catch (_) {
      return;
    }
    if (mounted &&
        generation == _contextOverlayGeneration &&
        _contextOverlay == _PlayerContextOverlay.speed) {
      _closeContextOverlay();
    }
  }

  void _selectFit(UnifiedVideoFit fit) {
    _showControls();
    _ignorePlaybackError(() => widget.controller.setFit(fit));
  }

  void _selectKernel(String kernelId) {
    _showControls();
    _ignorePlaybackError(() => widget.controller.switchKernel(kernelId));
  }

  void _changeLegacySource() {
    if (widget.episodes.isEmpty) {
      _showControls();
      widget.onSwitchContent?.call();
    }
  }

  void _startScrubbing() {
    _scrubbing = true;
    _showControls();
  }

  void _endScrubbing() {
    _scrubbing = false;
    _scheduleAutoHideIfNeeded();
  }

  bool _canAutoHide(UnifiedVideoState state) {
    if (_scrubbing ||
        (_contextOverlay != null && !_contextPanelController.isDismissed)) {
      return false;
    }
    switch (state.lifecycle) {
      case UnifiedVideoLifecycle.ready:
      case UnifiedVideoLifecycle.playing:
      case UnifiedVideoLifecycle.buffering:
        return true;
      case UnifiedVideoLifecycle.idle:
      case UnifiedVideoLifecycle.opening:
      case UnifiedVideoLifecycle.switchingKernel:
      case UnifiedVideoLifecycle.paused:
      case UnifiedVideoLifecycle.failed:
      case UnifiedVideoLifecycle.ended:
      case UnifiedVideoLifecycle.disposed:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UnifiedVideoState>(
      valueListenable: widget.controller,
      builder: (BuildContext context, UnifiedVideoState state, Widget? child) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool controlsShown =
                state.lifecycle != UnifiedVideoLifecycle.opening &&
                (_controlsVisible || !_canAutoHide(state));
            final PlayerViewMetrics metrics = PlayerViewMetrics.resolve(
              platform: widget.controller.platform,
              fullscreen: state.fullscreen,
              orientation: MediaQuery.orientationOf(context),
              width: constraints.maxWidth,
              viewPadding: MediaQuery.viewPaddingOf(context),
            );
            final bool desktopInput =
                widget.controller.platform == UnifiedVideoPlatform.windows ||
                widget.controller.platform == UnifiedVideoPlatform.macos ||
                widget.controller.platform == UnifiedVideoPlatform.linux;
            return MouseRegion(
              key: const ValueKey<String>('player-frame'),
              opaque: true,
              onEnter: desktopInput ? (_) => _showControls() : null,
              onHover: desktopInput ? (_) => _showControls() : null,
              child: Focus(
                autofocus: desktopInput,
                onKeyEvent: desktopInput
                    ? (FocusNode node, KeyEvent event) {
                        _showControls();
                        return KeyEventResult.ignored;
                      }
                    : null,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _showControls(),
                  onPointerMove: (_) => _showControls(),
                  onPointerSignal: (_) => _showControls(),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Colors.black),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Transform.rotate(
                          angle: _quarterTurns * math.pi / 2,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(
                              _mirrored ? -1.0 : 1.0,
                              1,
                              1,
                            ),
                            child: _VideoSurface(
                              controller: widget.controller,
                              state: state,
                            ),
                          ),
                        ),
                        if (_nightModeEnabled)
                          IgnorePointer(
                            child: ColoredBox(
                              key: const ValueKey<String>('night-mode-layer'),
                              color: Colors.black.withValues(alpha: 0.22),
                            ),
                          ),
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleControls,
                          ),
                        ),
                        PlayerStateOverlay(
                          controller: widget.controller,
                          state: state,
                          onRetry: _retryCurrentSource,
                          onResume: () {
                            _showControls();
                            _ignorePlaybackError(
                              () => _playOrReplay(widget.controller, state),
                            );
                          },
                          onReplay: () {
                            _showControls();
                            _ignorePlaybackError(
                              () => _playOrReplay(widget.controller, state),
                            );
                          },
                          onNext: widget.onNext,
                        ),
                        if (state.lastKernelSwitchError != null &&
                            state.lifecycle != UnifiedVideoLifecycle.failed)
                          Positioned(
                            left: 20,
                            right: 20,
                            top: 18,
                            child: IgnorePointer(
                              child: Semantics(
                                liveRegion: true,
                                child: DecoratedBox(
                                  key: const ValueKey<String>(
                                    'kernel-switch-error-message',
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.16,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      state.lastKernelSwitchError!.message,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_contextOverlay != null &&
                            !_contextPanelController.isDismissed)
                          _buildContextOverlay(metrics, constraints, state),
                        AnimatedOpacity(
                          key: const ValueKey<String>(
                            'player-controls-overlay',
                          ),
                          opacity: controlsShown ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          child: IgnorePointer(
                            ignoring: !controlsShown,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                if (metrics.mode != PlayerViewMode.compact)
                                  _PlayerTitleOverlay(
                                    controller: widget.controller,
                                    state: state,
                                    metrics: metrics,
                                  ),
                                Positioned.fill(
                                  child: PlayerControls(
                                    state: state,
                                    metrics: metrics,
                                    hasEpisodes: widget.episodes.isNotEmpty,
                                    danmakuEnabled: _danmakuEnabled,
                                    onPrevious: widget.onPrevious,
                                    onPlayPause: () {
                                      _showControls();
                                      if (state.isPlaying) {
                                        _ignorePlaybackError(
                                          widget.controller.pause,
                                        );
                                      } else {
                                        _ignorePlaybackError(
                                          () => _playOrReplay(
                                            widget.controller,
                                            state,
                                          ),
                                        );
                                      }
                                    },
                                    onNext: widget.onNext,
                                    onOpenEpisodes: () {
                                      _showControls();
                                      _toggleContextOverlay(
                                        _PlayerContextOverlay.episode,
                                      );
                                    },
                                    onToggleDanmaku: () {
                                      _showControls();
                                      setState(
                                        () =>
                                            _danmakuEnabled = !_danmakuEnabled,
                                      );
                                    },
                                    onOpenSpeed: () {
                                      _showControls();
                                      _toggleContextOverlay(
                                        _PlayerContextOverlay.speed,
                                      );
                                    },
                                    onOpenMore: () {
                                      _showControls();
                                      _toggleContextOverlay(
                                        _PlayerContextOverlay.settings,
                                      );
                                    },
                                    onToggleFullscreen: () {
                                      _showControls();
                                      _closeContextOverlay();
                                      _ignorePlaybackError(
                                        widget.onFullscreenPressed,
                                      );
                                    },
                                    onSeekStart: _startScrubbing,
                                    onSeek: (double value) {
                                      _showControls();
                                      _ignorePlaybackError(
                                        () => widget.controller.seek(
                                          Duration(milliseconds: value.round()),
                                        ),
                                      );
                                    },
                                    onSeekEnd: _endScrubbing,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContextOverlay(
    PlayerViewMetrics metrics,
    BoxConstraints constraints,
    UnifiedVideoState state,
  ) {
    final bool reducedMotion = _reduceMotion;
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _contextPanelAnimation,
        builder: (BuildContext context, Widget? child) {
          final _PlayerContextOverlay? overlay = _contextOverlay;
          if (overlay == null) {
            return const SizedBox.shrink();
          }
          final double progress = _contextPanelAnimation.value;
          final bool mobileSheet =
              overlay == _PlayerContextOverlay.settings &&
              metrics.mode == PlayerViewMode.expanded;
          final Offset offset;
          final Alignment transformAlignment;
          if (reducedMotion) {
            offset = Offset.zero;
          } else if (overlay == _PlayerContextOverlay.episode &&
              metrics.mode != PlayerViewMode.wide) {
            offset = Offset(24 * (1 - progress), 0);
          } else {
            offset = Offset(0, (mobileSheet ? 24 : 12) * (1 - progress));
          }
          if (overlay == _PlayerContextOverlay.episode &&
              metrics.mode != PlayerViewMode.wide) {
            transformAlignment = Alignment.centerRight;
          } else {
            transformAlignment = Alignment.bottomRight;
          }
          final Widget animatedPanel = IgnorePointer(
            ignoring: !_contextOverlayInteractive,
            child: Opacity(
              opacity: progress,
              child: Transform.translate(
                offset: offset,
                child: Transform.scale(
                  scale: reducedMotion ? 1 : 0.98 + (0.02 * progress),
                  alignment: transformAlignment,
                  child: _contextPanel(
                    overlay,
                    metrics,
                    state,
                    reducedMotion ? 1 : progress,
                  ),
                ),
              ),
            ),
          );
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              IgnorePointer(
                ignoring: !_contextOverlayInteractive,
                child: GestureDetector(
                  key: const ValueKey<String>('context-overlay-scrim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeContextOverlay,
                  child: ColoredBox(
                    color: mobileSheet
                        ? Colors.black.withValues(alpha: 0.28 * progress)
                        : Colors.transparent,
                  ),
                ),
              ),
              _positionContextPanel(
                overlay,
                metrics,
                constraints,
                animatedPanel,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _contextPanel(
    _PlayerContextOverlay overlay,
    PlayerViewMetrics metrics,
    UnifiedVideoState state,
    double materialProgress,
  ) {
    switch (overlay) {
      case _PlayerContextOverlay.episode:
        return PlayerEpisodePanel(
          key: const ValueKey<String>('episode-panel'),
          episodes: widget.episodes,
          activeEpisodeId: widget.activeEpisodeId,
          mode: metrics.mode,
          openingEpisodeId: widget.openingEpisodeId,
          materialProgress: materialProgress,
          onSelected: _selectEpisode,
          onClose: _closeContextOverlay,
        );
      case _PlayerContextOverlay.speed:
        return PlayerSpeedPanel(
          key: const ValueKey<String>('speed-panel'),
          state: state,
          materialProgress: materialProgress,
          onSelected: (double speed) => unawaited(_selectSpeed(speed)),
        );
      case _PlayerContextOverlay.settings:
        return PlayerSettingsPanel(
          key: const ValueKey<String>('settings-panel'),
          controller: widget.controller,
          state: state,
          mode: metrics.mode,
          danmakuEnabled: _danmakuEnabled,
          mirrored: _mirrored,
          quarterTurns: _quarterTurns,
          nightModeEnabled: _nightModeEnabled,
          onToggleDanmaku: () {
            _showControls();
            setState(() => _danmakuEnabled = !_danmakuEnabled);
          },
          onToggleMirror: () {
            _showControls();
            setState(() => _mirrored = !_mirrored);
          },
          onRotateLeft: () {
            _showControls();
            setState(() => _quarterTurns = (_quarterTurns + 3) % 4);
          },
          onRotateRight: () {
            _showControls();
            setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
          },
          onToggleNightMode: () {
            _showControls();
            setState(() => _nightModeEnabled = !_nightModeEnabled);
          },
          onSelectFit: _selectFit,
          onSelectKernel: _selectKernel,
          onChangeSource:
              widget.episodes.isEmpty && widget.onSwitchContent != null
              ? _changeLegacySource
              : null,
          onClose: _closeContextOverlay,
          materialProgress: materialProgress,
        );
    }
  }

  Widget _positionContextPanel(
    _PlayerContextOverlay overlay,
    PlayerViewMetrics metrics,
    BoxConstraints constraints,
    Widget panel,
  ) {
    switch (overlay) {
      case _PlayerContextOverlay.episode:
        if (metrics.mode == PlayerViewMode.wide) {
          return Positioned(
            right: 14,
            bottom: 52,
            width: 320,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: panel,
            ),
          );
        }
        return Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: math.min(360, constraints.maxWidth * 0.58),
          child: panel,
        );
      case _PlayerContextOverlay.speed:
        return Positioned(
          right: metrics.rightPadding + 44 + (metrics.showMore ? 44 : 0),
          bottom: metrics.bottomPadding + 52,
          width: 168,
          child: panel,
        );
      case _PlayerContextOverlay.settings:
        if (metrics.mode == PlayerViewMode.wide) {
          return Positioned(
            right: 14,
            bottom: 52,
            width: 380,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(0, constraints.maxHeight - 72),
              ),
              child: panel,
            ),
          );
        }
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight * 0.86,
            ),
            child: panel,
          ),
        );
    }
  }

  Future<void> _retryCurrentSource() async {
    final VideoSource? source = widget.controller.value.source;
    if (source != null) {
      try {
        await widget.controller.open(source);
      } catch (_) {
        // 控制器已经把失败原因写入 state，UI 不再把异常泄漏到 runtime。
      }
    }
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({required this.controller, required this.state});

  final UnifiedVideoController controller;
  final UnifiedVideoState state;

  @override
  Widget build(BuildContext context) {
    final adapter = controller.activeAdapter;
    return KeyedSubtree(
      key: const ValueKey<String>('video-surface-host'),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: state.lifecycle == UnifiedVideoLifecycle.switchingKernel
            ? 0
            : 1,
        child: adapter == null
            ? const SizedBox.expand()
            : FittedBox(
                fit: _boxFitFor(state.fit),
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: 1280,
                  height: 720,
                  child: adapter.buildSurface(context, state),
                ),
              ),
      ),
    );
  }

  BoxFit _boxFitFor(UnifiedVideoFit fit) {
    switch (fit) {
      case UnifiedVideoFit.original:
      case UnifiedVideoFit.contain:
      case UnifiedVideoFit.ratio16x9:
      case UnifiedVideoFit.ratio4x3:
        return BoxFit.contain;
      case UnifiedVideoFit.fill:
        return BoxFit.fill;
      case UnifiedVideoFit.cover:
        return BoxFit.cover;
    }
  }
}

class _PlayerTitleOverlay extends StatelessWidget {
  const _PlayerTitleOverlay({
    required this.controller,
    required this.state,
    required this.metrics,
  });

  final UnifiedVideoController controller;
  final UnifiedVideoState state;
  final PlayerViewMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final bool wide = metrics.mode == PlayerViewMode.wide;
    final double titleSize = wide ? 17 : 18;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.64),
                Colors.transparent,
              ],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              metrics.leftPadding,
              MediaQuery.viewPaddingOf(context).top + (wide ? 20 : 18),
              metrics.rightPadding,
              30,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _sourceTitle(state),
                  key: const ValueKey<String>('player-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w600,
                    fontVariations: const <FontVariation>[
                      FontVariation('wght', 650),
                    ],
                    letterSpacing: titleSize * -0.02,
                    shadows: const <Shadow>[
                      Shadow(
                        color: Color(0x8C000000),
                        offset: Offset(0, 1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _sourceSubtitle(controller, state),
                  key: const ValueKey<String>('player-subtitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: wide ? 10 : 11,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                    shadows: const <Shadow>[
                      Shadow(
                        color: Color(0x8C000000),
                        offset: Offset(0, 1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _sourceTitle(UnifiedVideoState state) {
  return state.source?.metadata.title ??
      state.source?.metadata.episodeTitle ??
      '统一影视播放器';
}

String _sourceSubtitle(
  UnifiedVideoController controller,
  UnifiedVideoState state,
) {
  final Object? resolution = state.source?.metadata.extra['resolution'];
  final String kernel = _activeKernelName(controller, state);
  if (resolution is String && resolution.trim().isNotEmpty) {
    return '$resolution / $kernel';
  }
  return '1280 x 720 / $kernel';
}

String _activeKernelName(
  UnifiedVideoController controller,
  UnifiedVideoState state,
) {
  final String? activeKernelId = state.activeKernelId;
  if (activeKernelId == null) {
    return '未选择内核';
  }
  for (final VideoKernelDescriptor descriptor in controller.availableKernels) {
    if (descriptor.id == activeKernelId) {
      return descriptor.displayName;
    }
  }
  return activeKernelId;
}

double _playerAspectRatio(double fallback, UnifiedVideoFit fit) {
  switch (fit) {
    case UnifiedVideoFit.original:
    case UnifiedVideoFit.contain:
    case UnifiedVideoFit.cover:
    case UnifiedVideoFit.fill:
      return fallback;
    case UnifiedVideoFit.ratio16x9:
      return 16 / 9;
    case UnifiedVideoFit.ratio4x3:
      return 4 / 3;
  }
}

Future<void> _playOrReplay(
  UnifiedVideoController controller,
  UnifiedVideoState state,
) async {
  if (state.lifecycle == UnifiedVideoLifecycle.ended) {
    await controller.seek(Duration.zero);
  }
  await controller.play();
}

void _ignorePlaybackError(Future<void> Function() action) {
  try {
    unawaited(action().catchError((_) {}));
  } catch (_) {
    // 控制器会通过 state 暴露错误，UI 控件不向 runtime 泄漏异常。
  }
}
