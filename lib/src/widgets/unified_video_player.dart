import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controller.dart';
import '../kernel.dart';
import '../models.dart';
import 'player_view/player_controls.dart';
import 'player_view/player_episode_panel.dart';
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
  VideoSource? _lastObservedSource;

  @override
  void initState() {
    super.initState();
    _validateEpisodes(widget.episodes);
    _lastObservedSource = widget.controller.value.source;
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
      _lastObservedSource = widget.controller.value.source;
      _syncActiveEpisodeFromSource();
    } else if (oldWidget.episodes != widget.episodes &&
        _episodeWithId(_activeEpisodeId) == null) {
      _syncActiveEpisodeFromSource();
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
    final VideoSource? source = widget.controller.value.source;
    if (!_sameSource(source, _lastObservedSource)) {
      if (_openingEpisodeId == null) {
        _lastObservedSource = source;
        _syncActiveEpisodeFromSource();
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
    setState(() => _openingEpisodeId = episode.id);
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
      });
      widget.onEpisodeChanged?.call(episode);
      return true;
    } finally {
      if (mounted &&
          widget.controller == openingController &&
          _episodeOperationGeneration == openingGeneration &&
          _openingEpisodeId == episode.id) {
        setState(() => _openingEpisodeId = null);
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

class _UnifiedVideoPlayerViewState extends State<_UnifiedVideoPlayerView>
    with SingleTickerProviderStateMixin {
  bool _controlsVisible = true;
  bool _episodePanelVisible = false;
  bool _scrubbing = false;
  bool _danmakuEnabled = false;
  bool _mirrored = false;
  int _quarterTurns = 0;
  Timer? _hideControlsTimer;
  UnifiedVideoLifecycle? _lastLifecycle;
  late bool _lastFullscreen;
  late final AnimationController _episodePanelController;
  late final Animation<double> _episodePanelAnimation;

  @override
  void initState() {
    super.initState();
    _lastLifecycle = widget.controller.value.lifecycle;
    _lastFullscreen = widget.controller.value.fullscreen;
    _episodePanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 260),
    )..addStatusListener(_handleEpisodePanelAnimationStatus);
    _episodePanelAnimation = CurvedAnimation(
      parent: _episodePanelController,
      curve: Curves.easeOutQuart,
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
      _closeEpisodePanel();
      _scheduleAutoHideIfNeeded();
    } else if (widget.episodes.isEmpty && oldWidget.episodes.isNotEmpty) {
      _closeEpisodePanel();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handlePlaybackStateChanged);
    _hideControlsTimer?.cancel();
    _episodePanelController
      ..removeStatusListener(_handleEpisodePanelAnimationStatus)
      ..dispose();
    super.dispose();
  }

  void _handleEpisodePanelAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() {});
    }
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
      _closeEpisodePanel();
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

  void _configureEpisodePanelMotion() {
    final Duration enter = Duration(milliseconds: _reduceMotion ? 200 : 400);
    final Duration exit = Duration(milliseconds: _reduceMotion ? 200 : 260);
    _episodePanelController
      ..duration = enter
      ..reverseDuration = exit;
  }

  void _toggleEpisodePanel() {
    if (_episodePanelVisible) {
      _closeEpisodePanel();
    } else {
      _openEpisodePanel();
    }
  }

  void _openEpisodePanel() {
    _hideControlsTimer?.cancel();
    _configureEpisodePanelMotion();
    setState(() => _episodePanelVisible = true);
    _episodePanelController.forward();
  }

  void _closeEpisodePanel() {
    if (!_episodePanelVisible && _episodePanelController.isDismissed) {
      return;
    }
    _configureEpisodePanelMotion();
    if (mounted) {
      setState(() => _episodePanelVisible = false);
    } else {
      _episodePanelVisible = false;
    }
    _episodePanelController.reverse();
    _scheduleAutoHideIfNeeded();
  }

  Future<void> _selectEpisode(VideoEpisode episode) async {
    try {
      final bool opened = await widget.onEpisodeSelected(episode);
      if (opened && mounted) {
        _closeEpisodePanel();
      }
    } catch (_) {
      // The controller exposes the failed state; keep the picker available.
    }
  }

  void _openContextSettings() {
    _closeEpisodePanel();
    _ignorePlaybackError(_openSettingsSheet);
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
    if (_scrubbing) {
      return false;
    }
    switch (state.lifecycle) {
      case UnifiedVideoLifecycle.ready:
      case UnifiedVideoLifecycle.playing:
      case UnifiedVideoLifecycle.paused:
      case UnifiedVideoLifecycle.ended:
        return true;
      case UnifiedVideoLifecycle.idle:
      case UnifiedVideoLifecycle.opening:
      case UnifiedVideoLifecycle.switchingKernel:
      case UnifiedVideoLifecycle.buffering:
      case UnifiedVideoLifecycle.failed:
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
            final bool controlsShown = _controlsVisible || !_canAutoHide(state);
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
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleControls,
                          ),
                        ),
                        _StateOverlay(
                          controller: widget.controller,
                          state: state,
                          onRetry: _retryCurrentSource,
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
                        if (metrics.showEpisodePicker &&
                            widget.episodes.isNotEmpty &&
                            (_episodePanelVisible ||
                                !_episodePanelController.isDismissed))
                          _buildEpisodePanel(metrics, constraints),
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
                                      _toggleEpisodePanel();
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
                                      _openContextSettings();
                                    },
                                    onOpenMore: () {
                                      _showControls();
                                      _openContextSettings();
                                    },
                                    onToggleFullscreen: () {
                                      _showControls();
                                      _closeEpisodePanel();
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

  Widget _buildEpisodePanel(
    PlayerViewMetrics metrics,
    BoxConstraints constraints,
  ) {
    final bool reducedMotion = _reduceMotion;
    final Alignment transformAlignment = metrics.mode == PlayerViewMode.wide
        ? Alignment.bottomRight
        : Alignment.centerRight;
    final Widget animatedPanel = AnimatedBuilder(
      animation: _episodePanelAnimation,
      builder: (BuildContext context, Widget? child) {
        final double progress = _episodePanelAnimation.value;
        final Offset offset = reducedMotion
            ? Offset.zero
            : metrics.mode == PlayerViewMode.wide
            ? Offset(0, 12 * (1 - progress))
            : Offset(24 * (1 - progress), 0);
        return IgnorePointer(
          ignoring: !_episodePanelVisible,
          child: Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: offset,
              child: Transform.scale(
                scale: reducedMotion ? 1 : 0.98 + (0.02 * progress),
                alignment: transformAlignment,
                child: PlayerEpisodePanel(
                  key: const ValueKey<String>('episode-panel'),
                  episodes: widget.episodes,
                  activeEpisodeId: widget.activeEpisodeId,
                  mode: metrics.mode,
                  openingEpisodeId: widget.openingEpisodeId,
                  materialProgress: reducedMotion ? 1 : progress,
                  onSelected: _selectEpisode,
                  onClose: _closeEpisodePanel,
                ),
              ),
            ),
          ),
        );
      },
    );

    if (metrics.mode == PlayerViewMode.wide) {
      return Positioned(
        right: 14,
        bottom: 52,
        width: 320,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: animatedPanel,
        ),
      );
    }
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: math.min(360, constraints.maxWidth * 0.58),
      child: animatedPanel,
    );
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

  Future<void> _openSettingsSheet() async {
    _hideControlsTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return ValueListenableBuilder<UnifiedVideoState>(
              valueListenable: widget.controller,
              builder:
                  (
                    BuildContext context,
                    UnifiedVideoState state,
                    Widget? child,
                  ) {
                    return _PlayerSettingsPanel(
                      controller: widget.controller,
                      state: state,
                      danmakuEnabled: _danmakuEnabled,
                      mirrored: _mirrored,
                      quarterTurns: _quarterTurns,
                      onToggleDanmaku: () {
                        _showControls();
                        setState(() => _danmakuEnabled = !_danmakuEnabled);
                        setModalState(() {});
                      },
                      onToggleMirror: () {
                        _showControls();
                        setState(() => _mirrored = !_mirrored);
                        setModalState(() {});
                      },
                      onRotateLeft: () {
                        _showControls();
                        setState(() => _quarterTurns = (_quarterTurns + 3) % 4);
                        setModalState(() {});
                      },
                      onRotateRight: () {
                        _showControls();
                        setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
                        setModalState(() {});
                      },
                      onUserInteraction: _showControls,
                      onClose: () {
                        Navigator.of(context).maybePop();
                      },
                    );
                  },
            );
          },
        );
      },
    );
    if (mounted) {
      _scheduleAutoHideIfNeeded();
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

class _StateOverlay extends StatelessWidget {
  const _StateOverlay({
    required this.controller,
    required this.state,
    required this.onRetry,
  });

  final UnifiedVideoController controller;
  final UnifiedVideoState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (state.lifecycle) {
      case UnifiedVideoLifecycle.opening:
      case UnifiedVideoLifecycle.switchingKernel:
      case UnifiedVideoLifecycle.buffering:
        final bool buffering =
            state.lifecycle == UnifiedVideoLifecycle.buffering;
        final bool switching =
            state.lifecycle == UnifiedVideoLifecycle.switchingKernel;
        final String loadingText = buffering
            ? '正在缓冲'
            : switching
            ? '正在切换到 ${_kernelDisplayName(controller, state.targetKernelId)}'
            : '正在加载视频';
        return IgnorePointer(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.32),
            child: Center(
              child: Semantics(
                liveRegion: true,
                label: loadingText,
                child: Column(
                  key: const ValueKey<String>('video-loading-indicator'),
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox.square(
                      dimension: 30,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loadingText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      case UnifiedVideoLifecycle.failed:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, color: Colors.white, size: 42),
              const SizedBox(height: 10),
              Text(
                state.error?.message ?? '播放失败',
                key: const ValueKey<String>('video-error-message'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        );
      case UnifiedVideoLifecycle.ended:
        return const SizedBox.shrink();
      case UnifiedVideoLifecycle.idle:
      case UnifiedVideoLifecycle.ready:
      case UnifiedVideoLifecycle.playing:
      case UnifiedVideoLifecycle.paused:
      case UnifiedVideoLifecycle.disposed:
        return const SizedBox.shrink();
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

class _PlayerSettingsPanel extends StatelessWidget {
  const _PlayerSettingsPanel({
    required this.controller,
    required this.state,
    required this.danmakuEnabled,
    required this.mirrored,
    required this.quarterTurns,
    required this.onToggleDanmaku,
    required this.onToggleMirror,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onUserInteraction,
    required this.onClose,
  });

  final UnifiedVideoController controller;
  final UnifiedVideoState state;
  final bool danmakuEnabled;
  final bool mirrored;
  final int quarterTurns;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onToggleMirror;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onUserInteraction;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1F1F1F).withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 9, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        '播放设置',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        _sourceSubtitle(controller, state),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.56),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SettingsSection(
                  title: '播放',
                  child: _SettingsButtonGrid(
                    children: <Widget>[
                      _SettingsChip(
                        key: const ValueKey<String>('danmaku-toggle'),
                        selected: danmakuEnabled,
                        label: '弹幕',
                        onPressed: () {
                          onToggleDanmaku();
                          onClose();
                        },
                      ),
                      _SettingsChip(
                        key: const ValueKey<String>('mirror-toggle'),
                        selected: mirrored,
                        label: '镜像',
                        onPressed: () {
                          onToggleMirror();
                          onClose();
                        },
                      ),
                      _SettingsChip(
                        key: const ValueKey<String>('rotation-left'),
                        selected: false,
                        label: '左转',
                        onPressed: () {
                          onRotateLeft();
                          onClose();
                        },
                      ),
                      _SettingsChip(
                        key: const ValueKey<String>('rotation-right'),
                        selected: false,
                        label: '右转',
                        onPressed: () {
                          onRotateRight();
                          onClose();
                        },
                      ),
                    ],
                  ),
                ),
                _SettingsSection(
                  key: const ValueKey<String>('kernel-menu'),
                  title: '播放器内核',
                  child: _SettingsButtonGrid(
                    children: controller.compatibleKernels
                        .map((VideoKernelDescriptor descriptor) {
                          final bool selected =
                              descriptor.id == state.activeKernelId;
                          return _SettingsChip(
                            key: ValueKey<String>(
                              'kernel-option-${descriptor.id}',
                            ),
                            selected: selected,
                            label: descriptor.displayName,
                            onPressed: () {
                              onUserInteraction();
                              if (!selected) {
                                _ignorePlaybackError(
                                  () => controller.switchKernel(descriptor.id),
                                );
                              }
                              onClose();
                            },
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
                _SettingsSection(
                  key: const ValueKey<String>('speed-menu'),
                  title: '播放倍速',
                  child: _SettingsButtonGrid(
                    children: unifiedVideoSpeedPresets
                        .map((double speed) {
                          return _SettingsChip(
                            key: ValueKey<String>('speed-option-$speed'),
                            selected: (state.speed - speed).abs() < 0.001,
                            label: '${speed}x',
                            onPressed: () {
                              onUserInteraction();
                              _ignorePlaybackError(
                                () => controller.setSpeed(speed),
                              );
                              onClose();
                            },
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
                _SettingsSection(
                  key: const ValueKey<String>('fit-menu'),
                  title: '画面缩放',
                  child: _SettingsButtonGrid(
                    children: UnifiedVideoFit.values
                        .map((UnifiedVideoFit fit) {
                          return _SettingsChip(
                            key: ValueKey<String>('fit-option-${fit.name}'),
                            selected: state.fit == fit,
                            label: _fitLabel(fit),
                            onPressed: () {
                              onUserInteraction();
                              _ignorePlaybackError(
                                () => controller.setFit(fit),
                              );
                              onClose();
                            },
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
                _SettingsSection(
                  title: '状态',
                  child: _SettingsButtonGrid(
                    children: <Widget>[
                      _SettingsChip(
                        selected: true,
                        label: '旋转 ${quarterTurns * 90}°',
                        onPressed: null,
                      ),
                      _SettingsChip(
                        selected: state.fullscreen,
                        label: state.fullscreen ? '全屏中' : '非全屏',
                        onPressed: null,
                      ),
                      _SettingsChip(
                        selected:
                            state.lifecycle == UnifiedVideoLifecycle.ended,
                        label: state.lifecycle == UnifiedVideoLifecycle.ended
                            ? '已结束'
                            : '播放中',
                        onPressed: null,
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

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _SettingsButtonGrid extends StatelessWidget {
  const _SettingsButtonGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int columns = width >= 620
            ? 5
            : width >= 480
            ? 4
            : 3;
        final double itemWidth = (width - (columns - 1) * 7) / columns;
        return Wrap(
          spacing: 7,
          runSpacing: 6,
          children: children
              .map((Widget child) => SizedBox(width: itemWidth, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}

class _SettingsChip extends StatelessWidget {
  const _SettingsChip({
    super.key,
    required this.selected,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected
        ? const Color(0xFF7EC3FF)
        : onPressed == null
        ? Colors.white.withValues(alpha: 0.52)
        : Colors.white;
    return SizedBox(
      height: 44,
      child: Material(
        color: selected
            ? const Color(0xFF7EC3FF).withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: selected
                    ? const Color(0xFF7EC3FF).withValues(alpha: 0.48)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
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

String _kernelDisplayName(UnifiedVideoController controller, String? kernelId) {
  if (kernelId == null) {
    return '目标内核';
  }
  for (final VideoKernelDescriptor descriptor in controller.availableKernels) {
    if (descriptor.id == kernelId) {
      return descriptor.displayName;
    }
  }
  return kernelId;
}

String _fitLabel(UnifiedVideoFit fit) {
  switch (fit) {
    case UnifiedVideoFit.original:
      return '原始';
    case UnifiedVideoFit.ratio16x9:
      return '16:9';
    case UnifiedVideoFit.ratio4x3:
      return '4:3';
    case UnifiedVideoFit.contain:
      return '适应';
    case UnifiedVideoFit.fill:
      return '填充';
    case UnifiedVideoFit.cover:
      return '裁剪';
  }
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
