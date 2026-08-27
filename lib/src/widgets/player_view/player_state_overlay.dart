import 'package:flutter/material.dart';

import '../../controller.dart';
import '../../kernel.dart';
import '../../models.dart';

class PlayerStateOverlay extends StatelessWidget {
  const PlayerStateOverlay({
    super.key,
    required this.controller,
    required this.state,
    required this.onRetry,
    required this.onResume,
    required this.onReplay,
    this.onNext,
  });

  final UnifiedVideoController controller;
  final UnifiedVideoState state;
  final VoidCallback onRetry;
  final VoidCallback onResume;
  final VoidCallback onReplay;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    switch (state.lifecycle) {
      case UnifiedVideoLifecycle.opening:
        return const _LoadingState(title: '正在加载视频', subtitle: '播放器内核初始化中');
      case UnifiedVideoLifecycle.buffering:
        return _LoadingState(
          title: '正在缓冲',
          subtitle: '${_formatDuration(state.position)} 已保留',
          subtitleKey: const ValueKey<String>('buffering-position'),
        );
      case UnifiedVideoLifecycle.switchingKernel:
        return _LoadingState(
          title:
              '正在切换到 ${_kernelDisplayName(controller, state.targetKernelId)}',
          subtitle: '当前播放位置与设置会保留',
        );
      case UnifiedVideoLifecycle.paused:
        return _PausedState(onResume: onResume);
      case UnifiedVideoLifecycle.failed:
        return _FailedState(state: state, onRetry: onRetry);
      case UnifiedVideoLifecycle.ended:
        return _EndedState(onReplay: onReplay, onNext: onNext);
      case UnifiedVideoLifecycle.idle:
      case UnifiedVideoLifecycle.ready:
      case UnifiedVideoLifecycle.playing:
      case UnifiedVideoLifecycle.disposed:
        return const SizedBox.shrink();
    }
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({
    required this.title,
    required this.subtitle,
    this.subtitleKey,
  });

  final String title;
  final String subtitle;
  final Key? subtitleKey;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.18),
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: '$title，$subtitle',
            child: Column(
              key: const ValueKey<String>('video-loading-indicator'),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  key: subtitleKey,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
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

class _PausedState extends StatelessWidget {
  const _PausedState({required this.onResume});

  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '已暂停，继续播放',
      child: GestureDetector(
        key: const ValueKey<String>('paused-state-indicator'),
        behavior: HitTestBehavior.opaque,
        onTap: onResume,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 128, minHeight: 44),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                  SizedBox(height: 6),
                  Text(
                    '已暂停',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '点击画面继续播放',
                    style: TextStyle(color: Color(0x9EFFFFFF), fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FailedState extends StatelessWidget {
  const _FailedState({required this.state, required this.onRetry});

  final UnifiedVideoState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.18),
      child: Center(
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 30,
              ),
              const SizedBox(height: 9),
              const Text(
                '播放失败',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  state.error?.message ?? '请检查网络或切换播放内核',
                  key: const ValueKey<String>('video-error-message'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey<String>('state-retry'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(88, 44),
                  backgroundColor: const Color(0xFF0071E3),
                  foregroundColor: Colors.white,
                ),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndedState extends StatelessWidget {
  const _EndedState({required this.onReplay, required this.onNext});

  final VoidCallback onReplay;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.18),
      child: Center(
        child: Column(
          key: const ValueKey<String>('ended-state-indicator'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.replay_rounded, color: Colors.white, size: 30),
            const SizedBox(height: 9),
            const Text(
              '本集已结束',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FilledButton.icon(
                  key: const ValueKey<String>('state-replay'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(96, 44),
                    backgroundColor: const Color(0xFF0071E3),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onReplay,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('重播'),
                ),
                if (onNext != null) ...<Widget>[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('state-next'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(96, 44),
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    onPressed: onNext,
                    icon: const Icon(Icons.skip_next_rounded, size: 18),
                    label: const Text('下一集'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
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

String _formatDuration(Duration duration) {
  final int totalSeconds = duration.inSeconds.clamp(0, 359999);
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final String minuteText = hours > 0
      ? minutes.toString().padLeft(2, '0')
      : minutes.toString();
  final String secondText = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minuteText:$secondText';
  }
  return '$minuteText:$secondText';
}
