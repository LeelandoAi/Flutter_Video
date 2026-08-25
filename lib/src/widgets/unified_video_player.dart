import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controller.dart';
import '../kernel.dart';
import '../models.dart';

class UnifiedVideoPlayer extends StatefulWidget {
  const UnifiedVideoPlayer({
    super.key,
    required this.controller,
    this.onPrevious,
    this.onNext,
    this.onSwitchContent,
    this.aspectRatio = 16 / 9,
    this.autoHideControlsDelay = const Duration(seconds: 3),
  });

  final UnifiedVideoController controller;
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

  @override
  void initState() {
    super.initState();
    widget.controller.claimFullscreenOwnershipIfUnclaimed();
    widget.controller.addListener(_handleControllerFullscreenChanged);
  }

  @override
  void didUpdateWidget(covariant UnifiedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerFullscreenChanged);
      oldWidget.controller.releaseFullscreenOwnership();
      widget.controller.claimFullscreenOwnershipIfUnclaimed();
      widget.controller.addListener(_handleControllerFullscreenChanged);
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
      onPrevious: widget.onPrevious,
      onNext: widget.onNext,
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
    if (!mounted || _fullscreenTransitioning) {
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
}

class _UnifiedVideoPlayerView extends StatefulWidget {
  const _UnifiedVideoPlayerView({
    super.key,
    required this.controller,
    required this.onPrevious,
    required this.onNext,
    required this.onSwitchContent,
    required this.onFullscreenPressed,
    required this.autoHideControlsDelay,
  });

  final UnifiedVideoController controller;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSwitchContent;
  final Future<void> Function() onFullscreenPressed;
  final Duration autoHideControlsDelay;

  @override
  State<_UnifiedVideoPlayerView> createState() =>
      _UnifiedVideoPlayerViewState();
}

class _UnifiedVideoPlayerViewState extends State<_UnifiedVideoPlayerView> {
  bool _controlsVisible = true;
  bool _scrubbing = false;
  bool _danmakuEnabled = false;
  bool _favorite = false;
  bool _mirrored = false;
  bool _nightMode = false;
  int _quarterTurns = 0;
  Timer? _hideControlsTimer;
  UnifiedVideoLifecycle? _lastLifecycle;

  @override
  void initState() {
    super.initState();
    _lastLifecycle = widget.controller.value.lifecycle;
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
      _scheduleAutoHideIfNeeded();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handlePlaybackStateChanged);
    _hideControlsTimer?.cancel();
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
        final bool controlsShown = _controlsVisible || !_canAutoHide(state);
        final Widget player = Listener(
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
                if (_nightMode)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.18),
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
                              color: Colors.white.withValues(alpha: 0.16),
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
                AnimatedOpacity(
                  key: const ValueKey<String>('player-controls-overlay'),
                  opacity: controlsShown ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: IgnorePointer(
                    ignoring: !controlsShown,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _PlayerTopBar(
                          controller: widget.controller,
                          state: state,
                          favorite: _favorite,
                          nightMode: _nightMode,
                          onBackPressed: widget.onFullscreenPressed,
                          onToggleFavorite: () {
                            _showControls();
                            setState(() => _favorite = !_favorite);
                          },
                          onToggleNightMode: () {
                            _showControls();
                            setState(() => _nightMode = !_nightMode);
                          },
                          onOpenSettings: () {
                            _showControls();
                            _openSettingsSheet();
                          },
                        ),
                        _CenterTransportLayer(
                          controller: widget.controller,
                          state: state,
                          onPrevious: widget.onPrevious,
                          onNext: widget.onNext,
                          danmakuEnabled: _danmakuEnabled,
                          onToggleDanmaku: () {
                            _showControls();
                            setState(() => _danmakuEnabled = !_danmakuEnabled);
                          },
                          onRotateRight: () {
                            _showControls();
                            setState(
                              () => _quarterTurns = (_quarterTurns + 1) % 4,
                            );
                          },
                          onUserInteraction: _showControls,
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _PlayerBottomControls(
                            controller: widget.controller,
                            state: state,
                            onPrevious: widget.onPrevious,
                            onNext: widget.onNext,
                            onSwitchContent: widget.onSwitchContent,
                            onFullscreenPressed: widget.onFullscreenPressed,
                            onOpenSettings: _openSettingsSheet,
                            onToggleMirror: () {
                              _showControls();
                              setState(() => _mirrored = !_mirrored);
                            },
                            onToggleNightMode: () {
                              _showControls();
                              setState(() => _nightMode = !_nightMode);
                            },
                            mirrored: _mirrored,
                            nightMode: _nightMode,
                            onUserInteraction: _showControls,
                            onScrubStart: _startScrubbing,
                            onScrubEnd: _endScrubbing,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        return player;
      },
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

class _PlayerTopBar extends StatelessWidget {
  const _PlayerTopBar({
    required this.controller,
    required this.state,
    required this.favorite,
    required this.nightMode,
    required this.onBackPressed,
    required this.onToggleFavorite,
    required this.onToggleNightMode,
    required this.onOpenSettings,
  });

  final UnifiedVideoController controller;
  final UnifiedVideoState state;
  final bool favorite;
  final bool nightMode;
  final Future<void> Function() onBackPressed;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleNightMode;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.black.withValues(alpha: 0.72),
              Colors.black.withValues(alpha: 0),
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 30),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool compact = constraints.maxWidth < 460;
                final bool wide = constraints.maxWidth >= 620;
                return Row(
                  children: <Widget>[
                    _TopIconButton(
                      key: const ValueKey<String>('player-back'),
                      onPressed: () {
                        if (state.fullscreen) {
                          _ignorePlaybackError(onBackPressed);
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                      tooltip: state.fullscreen ? '退出全屏' : '返回',
                      icon: Icons.arrow_back_ios_new,
                      compact: compact,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _VideoTitleBlock(
                        title: _sourceTitle(state),
                        subtitle: _sourceSubtitle(controller, state),
                        compact: compact,
                      ),
                    ),
                    if (wide)
                      _TopIconButton(
                        key: const ValueKey<String>('cast'),
                        onPressed: null,
                        tooltip: '投屏',
                        icon: Icons.cast,
                      ),
                    if (!compact)
                      _TopIconButton(
                        key: const ValueKey<String>('night-mode'),
                        onPressed: onToggleNightMode,
                        tooltip: nightMode ? '关闭夜间模式' : '夜间模式',
                        icon: nightMode
                            ? Icons.dark_mode
                            : Icons.nightlight_round,
                      ),
                    if (!compact)
                      _TopIconButton(
                        key: const ValueKey<String>('favorite'),
                        onPressed: onToggleFavorite,
                        tooltip: favorite ? '取消常亮' : '保持常亮',
                        icon: favorite ? Icons.bookmark : Icons.bookmark_border,
                      ),
                    if (!compact)
                      _TopIconButton(
                        key: const ValueKey<String>('info'),
                        onPressed: null,
                        tooltip: '信息',
                        icon: Icons.info_outline,
                      ),
                    _TopIconButton(
                      key: const ValueKey<String>('settings-menu'),
                      onPressed: onOpenSettings,
                      tooltip: '播放设置',
                      icon: Icons.settings,
                      compact: compact,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoTitleBlock extends StatelessWidget {
  const _VideoTitleBlock({
    required this.title,
    required this.subtitle,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 13 : 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (!compact) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 11,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

class _CenterTransportLayer extends StatelessWidget {
  const _CenterTransportLayer({
    required this.controller,
    required this.state,
    required this.onPrevious,
    required this.onNext,
    required this.danmakuEnabled,
    required this.onToggleDanmaku,
    required this.onRotateRight,
    required this.onUserInteraction,
  });

  final UnifiedVideoController controller;
  final UnifiedVideoState state;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool danmakuEnabled;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onRotateRight;
  final VoidCallback onUserInteraction;

  @override
  Widget build(BuildContext context) {
    if (state.lifecycle == UnifiedVideoLifecycle.opening ||
        state.lifecycle == UnifiedVideoLifecycle.switchingKernel ||
        state.lifecycle == UnifiedVideoLifecycle.buffering ||
        state.lifecycle == UnifiedVideoLifecycle.failed ||
        state.lifecycle == UnifiedVideoLifecycle.disposed) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 360;
        final bool embedded = constraints.maxWidth < 430;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _TransportIconButton(
                    key: const ValueKey<String>('previous-episode'),
                    onPressed: onPrevious == null
                        ? null
                        : () {
                            onUserInteraction();
                            onPrevious!();
                          },
                    tooltip: '上一集',
                    icon: Icons.skip_previous,
                    size: compact ? 44 : 52,
                  ),
                  SizedBox(width: compact ? 14 : 20),
                  _TransportIconButton(
                    key: const ValueKey<String>('play-pause'),
                    onPressed: () {
                      onUserInteraction();
                      if (state.isPlaying) {
                        _ignorePlaybackError(controller.pause);
                      } else {
                        _ignorePlaybackError(
                          () => _playOrReplay(controller, state),
                        );
                      }
                    },
                    tooltip: state.isPlaying ? '暂停' : '播放',
                    icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: compact ? 54 : 64,
                    iconSize: compact ? 30 : 36,
                  ),
                  SizedBox(width: compact ? 14 : 20),
                  _TransportIconButton(
                    key: const ValueKey<String>('next-episode'),
                    onPressed: onNext == null
                        ? null
                        : () {
                            onUserInteraction();
                            onNext!();
                          },
                    tooltip: '下一集',
                    icon: Icons.skip_next,
                    size: compact ? 44 : 52,
                  ),
                ],
              ),
            ),
            if (!embedded)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _TopIconButton(
                    key: const ValueKey<String>('danmaku-toggle'),
                    onPressed: () {
                      onUserInteraction();
                      onToggleDanmaku();
                    },
                    tooltip: danmakuEnabled ? '关闭弹幕' : '打开弹幕',
                    icon: danmakuEnabled
                        ? Icons.chat_bubble
                        : Icons.chat_bubble_outline,
                  ),
                ),
              ),
            if (!embedded)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _TopIconButton(
                        key: const ValueKey<String>('rotate'),
                        onPressed: () {
                          onUserInteraction();
                          onRotateRight();
                        },
                        tooltip: '旋转',
                        icon: Icons.screen_rotation_alt_outlined,
                      ),
                      _TopIconButton(
                        key: const ValueKey<String>('pip'),
                        onPressed: null,
                        tooltip: '小窗播放',
                        icon: Icons.picture_in_picture_alt,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlayerBottomControls extends StatelessWidget {
  const _PlayerBottomControls({
    required this.controller,
    required this.state,
    required this.onPrevious,
    required this.onNext,
    required this.onSwitchContent,
    required this.onFullscreenPressed,
    required this.onOpenSettings,
    required this.onToggleMirror,
    required this.onToggleNightMode,
    required this.mirrored,
    required this.nightMode,
    required this.onUserInteraction,
    required this.onScrubStart,
    required this.onScrubEnd,
  });

  final UnifiedVideoController controller;
  final UnifiedVideoState state;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSwitchContent;
  final Future<void> Function() onFullscreenPressed;
  final Future<void> Function() onOpenSettings;
  final VoidCallback onToggleMirror;
  final VoidCallback onToggleNightMode;
  final bool mirrored;
  final bool nightMode;
  final VoidCallback onUserInteraction;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool embedded = constraints.maxWidth < 430;
        final int durationMs = state.duration.inMilliseconds;
        final int positionMs = state.position.inMilliseconds.clamp(
          0,
          durationMs,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: embedded ? 0 : 0.2),
                Colors.black.withValues(alpha: embedded ? 0.56 : 0.5),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: embedded
                  ? const EdgeInsets.fromLTRB(8, 10, 4, 4)
                  : const EdgeInsets.fromLTRB(16, 14, 4, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!embedded) ...<Widget>[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          _ControlTextButton(
                            key: const ValueKey<String>('action-play-pause'),
                            label: state.isPlaying ? '暂停' : '播放',
                            selected: state.isPlaying,
                            onPressed: () {
                              onUserInteraction();
                              if (state.isPlaying) {
                                _ignorePlaybackError(controller.pause);
                              } else {
                                _ignorePlaybackError(
                                  () => _playOrReplay(controller, state),
                                );
                              }
                            },
                          ),
                          _ControlTextButton(
                            key: const ValueKey<String>('next-episode-action'),
                            label: '下一集',
                            onPressed: onNext == null
                                ? null
                                : () {
                                    onUserInteraction();
                                    onNext!();
                                  },
                          ),
                          _ControlTextButton(
                            key: const ValueKey<String>(
                              'previous-episode-action',
                            ),
                            label: '上一集',
                            onPressed: onPrevious == null
                                ? null
                                : () {
                                    onUserInteraction();
                                    onPrevious!();
                                  },
                          ),
                          _ControlTextButton(
                            key: const ValueKey<String>('switch-content'),
                            label: '选集',
                            onPressed: onSwitchContent == null
                                ? null
                                : () {
                                    onUserInteraction();
                                    onSwitchContent!();
                                  },
                          ),
                          _ControlTextButton(
                            key: const ValueKey<String>('change-source'),
                            label: '换源',
                            onPressed: onSwitchContent == null
                                ? null
                                : () {
                                    onUserInteraction();
                                    onSwitchContent!();
                                  },
                          ),
                          _KernelActionMenu(
                            controller: controller,
                            state: state,
                            onUserInteraction: onUserInteraction,
                          ),
                          _SpeedActionMenu(
                            controller: controller,
                            state: state,
                            onUserInteraction: onUserInteraction,
                          ),
                          _FitActionMenu(
                            controller: controller,
                            state: state,
                            onUserInteraction: onUserInteraction,
                          ),
                          _ControlTextButton(
                            key: const ValueKey<String>('mirror-action'),
                            label: '镜像',
                            selected: mirrored,
                            onPressed: () {
                              onUserInteraction();
                              onToggleMirror();
                            },
                          ),
                          _ControlTextButton(
                            key: const ValueKey<String>('night-action'),
                            label: '夜间',
                            selected: nightMode,
                            onPressed: () {
                              onUserInteraction();
                              onToggleNightMode();
                            },
                          ),
                          _ControlTextButton(
                            key: const ValueKey<String>('advanced-settings'),
                            label: '设置',
                            onPressed: () {
                              onUserInteraction();
                              _ignorePlaybackError(onOpenSettings);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: <Widget>[
                      _TimeLabel(duration: state.position, compact: embedded),
                      SizedBox(width: embedded ? 4 : 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: embedded ? 3 : 4,
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: embedded ? 5 : 6,
                            ),
                            overlayShape: RoundSliderOverlayShape(
                              overlayRadius: embedded ? 10 : 14,
                            ),
                            activeTrackColor: const Color(0xFFFFD700),
                            inactiveTrackColor: Colors.white.withValues(
                              alpha: 0.4,
                            ),
                            thumbColor: Colors.white,
                            overlayColor: const Color(
                              0xFFFFD700,
                            ).withValues(alpha: 0.18),
                          ),
                          child: Slider(
                            key: const ValueKey<String>('video-progress'),
                            value: positionMs.toDouble(),
                            max: durationMs <= 0 ? 1 : durationMs.toDouble(),
                            onChangeStart: durationMs <= 0
                                ? null
                                : (_) {
                                    onScrubStart();
                                  },
                            onChangeEnd: durationMs <= 0
                                ? null
                                : (_) {
                                    onScrubEnd();
                                  },
                            onChanged: durationMs <= 0
                                ? null
                                : (double value) {
                                    onUserInteraction();
                                    _ignorePlaybackError(
                                      () => controller.seek(
                                        Duration(milliseconds: value.round()),
                                      ),
                                    );
                                  },
                          ),
                        ),
                      ),
                      SizedBox(width: embedded ? 4 : 8),
                      _TimeLabel(duration: state.duration, compact: embedded),
                      _TopIconButton(
                        key: const ValueKey<String>('fullscreen'),
                        onPressed: () => _ignorePlaybackError(() async {
                          onUserInteraction();
                          await onFullscreenPressed();
                        }),
                        tooltip: state.fullscreen ? '退出全屏' : '全屏',
                        icon: state.fullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        compact: embedded,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TransportIconButton extends StatelessWidget {
  const _TransportIconButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    required this.icon,
    required this.size,
    this.iconSize = 28,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: onPressed == null ? 0.24 : 0.5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
          tooltip: tooltip,
          iconSize: iconSize,
          icon: Icon(
            icon,
            color: onPressed == null
                ? Colors.white.withValues(alpha: 0.38)
                : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    required this.icon,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: compact ? 36 : 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          overlayColor: Colors.white.withValues(alpha: 0.14),
          shape: const CircleBorder(),
        ),
        icon: Icon(
          icon,
          size: compact ? 20 : 24,
          color: onPressed == null
              ? Colors.white.withValues(alpha: 0.34)
              : Colors.white,
        ),
      ),
    );
  }
}

class _ControlTextButton extends StatelessWidget {
  const _ControlTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final Color color = selected
        ? const Color(0xFFFFD700)
        : onPressed == null
        ? Colors.white.withValues(alpha: 0.36)
        : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _KernelActionMenu extends StatelessWidget {
  const _KernelActionMenu({
    required this.controller,
    required this.state,
    required this.onUserInteraction,
  });

  final UnifiedVideoController controller;
  final UnifiedVideoState state;
  final VoidCallback onUserInteraction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const ValueKey<String>('kernel-menu'),
      tooltip: '播放器内核',
      color: const Color(0xFF181818),
      onOpened: onUserInteraction,
      onSelected: (String kernelId) {
        onUserInteraction();
        _ignorePlaybackError(() => controller.switchKernel(kernelId));
      },
      itemBuilder: (BuildContext context) {
        return controller.compatibleKernels
            .map((VideoKernelDescriptor item) {
              return PopupMenuItem<String>(
                key: ValueKey<String>('kernel-option-${item.id}'),
                value: item.id,
                child: _MenuText(
                  item.displayName,
                  selected: item.id == state.activeKernelId,
                ),
              );
            })
            .toList(growable: false);
      },
      child: _ControlTextButton(
        label: _activeKernelShortName(controller, state),
        selected: true,
        onPressed: null,
      ),
    );
  }
}

class _SpeedActionMenu extends StatelessWidget {
  const _SpeedActionMenu({
    required this.controller,
    required this.state,
    required this.onUserInteraction,
  });

  final UnifiedVideoController controller;
  final UnifiedVideoState state;
  final VoidCallback onUserInteraction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      key: const ValueKey<String>('speed-menu'),
      tooltip: '播放倍速',
      color: const Color(0xFF181818),
      onOpened: onUserInteraction,
      onSelected: (double speed) {
        onUserInteraction();
        _ignorePlaybackError(() => controller.setSpeed(speed));
      },
      itemBuilder: (BuildContext context) {
        return unifiedVideoSpeedPresets
            .map((double speed) {
              return PopupMenuItem<double>(
                key: ValueKey<String>('speed-option-$speed'),
                value: speed,
                child: _MenuText(
                  '${speed}x',
                  selected: (state.speed - speed).abs() < 0.001,
                ),
              );
            })
            .toList(growable: false);
      },
      child: _ControlTextButton(
        label: '${state.speed}x',
        selected: true,
        onPressed: null,
      ),
    );
  }
}

class _FitActionMenu extends StatelessWidget {
  const _FitActionMenu({
    required this.controller,
    required this.state,
    required this.onUserInteraction,
  });

  final UnifiedVideoController controller;
  final UnifiedVideoState state;
  final VoidCallback onUserInteraction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<UnifiedVideoFit>(
      key: const ValueKey<String>('fit-menu'),
      tooltip: '画面缩放',
      color: const Color(0xFF181818),
      onOpened: onUserInteraction,
      onSelected: (UnifiedVideoFit fit) {
        onUserInteraction();
        _ignorePlaybackError(() => controller.setFit(fit));
      },
      itemBuilder: (BuildContext context) {
        return UnifiedVideoFit.values
            .map((UnifiedVideoFit fit) {
              return PopupMenuItem<UnifiedVideoFit>(
                key: ValueKey<String>('fit-option-${fit.name}'),
                value: fit,
                child: _MenuText(_fitLabel(fit), selected: state.fit == fit),
              );
            })
            .toList(growable: false);
      },
      child: _ControlTextButton(
        label: _fitLabel(state.fit),
        selected: true,
        onPressed: null,
      ),
    );
  }
}

class _MenuText extends StatelessWidget {
  const _MenuText(this.label, {required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: selected ? const Color(0xFFFFD700) : Colors.white,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.duration, this.compact = false});

  final Duration duration;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 32 : (duration.inHours > 0 ? 58 : 42),
      child: Text(
        _formatDuration(duration),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
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
        ? const Color(0xFFFFD700)
        : onPressed == null
        ? Colors.white.withValues(alpha: 0.52)
        : Colors.white;
    return SizedBox(
      height: 34,
      child: Material(
        color: selected
            ? const Color(0xFFFFD700).withValues(alpha: 0.10)
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
                    ? const Color(0xFFFFD700).withValues(alpha: 0.48)
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

String _activeKernelShortName(
  UnifiedVideoController controller,
  UnifiedVideoState state,
) {
  final String name = _activeKernelName(controller, state);
  if (name.contains('Erika')) {
    return 'Erika';
  }
  if (name.toLowerCase().contains('media')) {
    return 'MediaKit';
  }
  if (name.toLowerCase().contains('video')) {
    return 'Video';
  }
  return name.length > 10 ? '${name.substring(0, 10)}…' : name;
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

String _formatDuration(Duration duration) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  final int seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
