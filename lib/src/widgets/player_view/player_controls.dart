import 'package:flutter/material.dart';

import '../../models.dart';
import 'player_view_tokens.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.state,
    required this.metrics,
    required this.hasEpisodes,
    required this.danmakuEnabled,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onOpenEpisodes,
    required this.onToggleDanmaku,
    required this.onOpenSpeed,
    required this.onOpenMore,
    required this.onToggleFullscreen,
    required this.onSeekStart,
    required this.onSeek,
    required this.onSeekEnd,
  });

  final UnifiedVideoState state;
  final PlayerViewMetrics metrics;
  final bool hasEpisodes;
  final bool danmakuEnabled;
  final VoidCallback? onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback onOpenEpisodes;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onOpenSpeed;
  final VoidCallback onOpenMore;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeek;
  final VoidCallback onSeekEnd;

  @override
  Widget build(BuildContext context) {
    final int durationMs = state.duration.inMilliseconds;
    final int positionMs = state.position.inMilliseconds.clamp(0, durationMs);
    final TextStyle timeStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.8),
      fontSize: metrics.mode == PlayerViewMode.compact ? 8 : 11,
      fontWeight: FontWeight.w600,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      shadows: const <Shadow>[
        Shadow(color: Color(0xCC000000), offset: Offset(0, 1), blurRadius: 4),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.leftPadding,
        0,
        metrics.rightPadding,
        metrics.bottomPadding,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(_formatDuration(state.position), style: timeStyle),
              Text(_formatDuration(state.duration), style: timeStyle),
            ],
          ),
          SizedBox(
            height: 44,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: metrics.progressHeight,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.32),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withValues(alpha: 0.12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                key: const ValueKey<String>('video-progress'),
                value: positionMs.toDouble(),
                max: durationMs <= 0 ? 1 : durationMs.toDouble(),
                onChangeStart: durationMs <= 0 ? null : (_) => onSeekStart(),
                onChanged: durationMs <= 0 ? null : onSeek,
                onChangeEnd: durationMs <= 0 ? null : (_) => onSeekEnd(),
              ),
            ),
          ),
          Row(
            key: const ValueKey<String>('primary-controls-row'),
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _ControlHitTarget.icon(
                    key: const ValueKey<String>('previous-episode'),
                    semanticLabel: '上一集',
                    icon: Icons.skip_previous,
                    iconSize: metrics.iconSize,
                    onPressed: onPrevious,
                  ),
                  _ControlHitTarget.icon(
                    key: const ValueKey<String>('play-pause'),
                    semanticLabel: state.isPlaying ? '暂停' : '播放',
                    icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                    iconSize: metrics.primaryIconSize,
                    onPressed: onPlayPause,
                  ),
                  _ControlHitTarget.icon(
                    key: const ValueKey<String>('next-episode'),
                    semanticLabel: '下一集',
                    icon: Icons.skip_next,
                    iconSize: metrics.iconSize,
                    onPressed: onNext,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (hasEpisodes && metrics.showEpisodePicker)
                    _ControlHitTarget.text(
                      key: const ValueKey<String>('episode-picker'),
                      semanticLabel: '打开选集',
                      label: '选集',
                      fontSize: _textSize,
                      onPressed: onOpenEpisodes,
                    ),
                  _ControlHitTarget.icon(
                    key: const ValueKey<String>('danmaku-toggle'),
                    semanticLabel: danmakuEnabled ? '关闭弹幕' : '打开弹幕',
                    icon: danmakuEnabled
                        ? Icons.chat_bubble
                        : Icons.chat_bubble_outline,
                    iconSize: metrics.iconSize,
                    color: danmakuEnabled ? const Color(0xFF7EC3FF) : null,
                    toggled: danmakuEnabled,
                    onPressed: onToggleDanmaku,
                  ),
                  _ControlHitTarget.text(
                    key: const ValueKey<String>('speed-menu'),
                    semanticLabel: '播放速度 ${_speedLabel(state.speed)}',
                    label: _speedLabel(state.speed),
                    fontSize: _textSize,
                    onPressed: onOpenSpeed,
                  ),
                  if (metrics.showMore)
                    _ControlHitTarget.icon(
                      key: const ValueKey<String>('more-menu'),
                      semanticLabel: '更多设置',
                      icon: Icons.more_horiz,
                      iconSize: metrics.iconSize,
                      onPressed: onOpenMore,
                    ),
                  _ControlHitTarget.icon(
                    key: const ValueKey<String>('fullscreen'),
                    semanticLabel: state.fullscreen ? '退出全屏' : '进入全屏',
                    icon: state.fullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    iconSize: metrics.iconSize,
                    onPressed: onToggleFullscreen,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  double get _textSize => metrics.mode == PlayerViewMode.compact ? 9 : 13;

  String _speedLabel(double speed) {
    if (metrics.mode == PlayerViewMode.compact && speed == speed.round()) {
      return '${speed.round()}×';
    }
    return '${speed.toStringAsFixed(1)}×';
  }
}

class _ControlHitTarget extends StatelessWidget {
  const _ControlHitTarget._({
    super.key,
    required this.semanticLabel,
    required this.onPressed,
    required this.toggled,
    required this.child,
  });

  factory _ControlHitTarget.icon({
    Key? key,
    required String semanticLabel,
    required IconData icon,
    required double iconSize,
    Color? color,
    bool? toggled,
    required VoidCallback? onPressed,
  }) {
    return _ControlHitTarget._(
      key: key,
      semanticLabel: semanticLabel,
      onPressed: onPressed,
      toggled: toggled,
      child: Icon(
        icon,
        size: iconSize,
        color: color ?? _foreground(onPressed),
        shadows: const <Shadow>[
          Shadow(color: Color(0xCC000000), offset: Offset(0, 2), blurRadius: 6),
        ],
      ),
    );
  }

  factory _ControlHitTarget.text({
    Key? key,
    required String semanticLabel,
    required String label,
    required double fontSize,
    required VoidCallback? onPressed,
  }) {
    return _ControlHitTarget._(
      key: key,
      semanticLabel: semanticLabel,
      onPressed: onPressed,
      toggled: null,
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: _foreground(onPressed),
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          shadows: const <Shadow>[
            Shadow(
              color: Color(0xCC000000),
              offset: Offset(0, 2),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }

  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool? toggled;
  final Widget child;

  static Color _foreground(VoidCallback? onPressed) =>
      onPressed == null ? Colors.white.withValues(alpha: 0.34) : Colors.white;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      toggled: toggled,
      label: semanticLabel,
      child: MouseRegion(
        cursor: onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(dimension: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  final int seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
  return '${twoDigits(minutes)}:${twoDigits(seconds)}';
}
