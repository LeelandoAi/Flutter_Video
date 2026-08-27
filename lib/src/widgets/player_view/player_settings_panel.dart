import 'dart:ui';

import 'package:flutter/material.dart';

import '../../controller.dart';
import '../../kernel.dart';
import '../../models.dart';
import 'player_view_tokens.dart';

const Color _playerAccent = Color(0xFF7EC3FF);
const Color _opaqueGlass = Color(0xFF1E1E22);

class PlayerSpeedPanel extends StatelessWidget {
  const PlayerSpeedPanel({
    super.key,
    required this.state,
    required this.onSelected,
    this.materialProgress = 1,
  });

  final UnifiedVideoState state;
  final ValueChanged<double> onSelected;
  final double materialProgress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '播放速度',
      child: _PlayerGlassSurface(
        surfaceKey: const ValueKey<String>('speed-panel-surface'),
        borderRadius: BorderRadius.circular(18),
        materialProgress: materialProgress,
        child: SingleChildScrollView(
          key: const ValueKey<String>('speed-options-scroll'),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _withHairlines(
              unifiedVideoSpeedPresets
                  .map((double speed) {
                    return _SettingsOptionRow(
                      key: ValueKey<String>('speed-option-$speed'),
                      label: _speedLabel(speed),
                      selected: (state.speed - speed).abs() < 0.001,
                      minimumHeight: 44,
                      onPressed: () => onSelected(speed),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerSettingsPanel extends StatelessWidget {
  const PlayerSettingsPanel({
    super.key,
    required this.controller,
    required this.state,
    required this.mode,
    required this.danmakuEnabled,
    required this.mirrored,
    required this.quarterTurns,
    required this.nightModeEnabled,
    required this.onToggleDanmaku,
    required this.onToggleMirror,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onToggleNightMode,
    required this.onSelectFit,
    required this.onSelectKernel,
    required this.onClose,
    this.onChangeSource,
    this.materialProgress = 1,
  });

  final UnifiedVideoController controller;
  final UnifiedVideoState state;
  final PlayerViewMode mode;
  final bool danmakuEnabled;
  final bool mirrored;
  final int quarterTurns;
  final bool nightModeEnabled;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onToggleMirror;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onToggleNightMode;
  final ValueChanged<UnifiedVideoFit> onSelectFit;
  final ValueChanged<String> onSelectKernel;
  final VoidCallback onClose;
  final VoidCallback? onChangeSource;
  final double materialProgress;

  @override
  Widget build(BuildContext context) {
    final bool sheet = mode == PlayerViewMode.expanded;
    final double bottomInset = sheet
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0;
    final BorderRadius radius = sheet
        ? const BorderRadius.vertical(top: Radius.circular(22))
        : BorderRadius.circular(18);

    return Semantics(
      container: true,
      label: '播放设置',
      child: _PlayerGlassSurface(
        surfaceKey: const ValueKey<String>('settings-panel-surface'),
        borderRadius: radius,
        materialProgress: materialProgress,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 18 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (sheet) ...<Widget>[
                Center(
                  child: Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
              ],
              _SettingsHeader(
                subtitle: _activeKernelName(controller, state),
                onClose: onClose,
              ),
              const SizedBox(height: 10),
              _SettingsGroup(
                key: const ValueKey<String>('settings-group-picture'),
                surfaceKey: const ValueKey<String>(
                  'settings-group-picture-surface',
                ),
                title: '画面',
                children: <Widget>[
                  _FitOptionsRow(
                    selectedFit: state.fit,
                    onSelected: onSelectFit,
                  ),
                  _SettingsToggleRow(
                    key: const ValueKey<String>('mirror-toggle'),
                    label: '镜像',
                    value: mirrored,
                    onChanged: onToggleMirror,
                  ),
                  _RotationRow(
                    quarterTurns: quarterTurns,
                    onRotateLeft: onRotateLeft,
                    onRotateRight: onRotateRight,
                  ),
                  _SettingsToggleRow(
                    key: const ValueKey<String>('night-mode-toggle'),
                    label: '夜间模式',
                    value: nightModeEnabled,
                    onChanged: onToggleNightMode,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsGroup(
                key: const ValueKey<String>('settings-group-playback'),
                surfaceKey: const ValueKey<String>(
                  'settings-group-playback-surface',
                ),
                title: '播放',
                children: <Widget>[
                  _SettingsToggleRow(
                    key: const ValueKey<String>('danmaku-toggle'),
                    label: '弹幕',
                    value: danmakuEnabled,
                    onChanged: onToggleDanmaku,
                  ),
                  if (onChangeSource != null)
                    _SettingsActionRow(
                      key: const ValueKey<String>('change-source'),
                      label: '更换播放源',
                      onPressed: onChangeSource!,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsGroup(
                key: const ValueKey<String>('settings-group-kernel'),
                surfaceKey: const ValueKey<String>(
                  'settings-group-kernel-surface',
                ),
                title: '播放器内核',
                children: controller.compatibleKernels
                    .map((VideoKernelDescriptor descriptor) {
                      final bool selected =
                          descriptor.id == state.activeKernelId;
                      final bool switching =
                          state.lifecycle ==
                          UnifiedVideoLifecycle.switchingKernel;
                      return _SettingsOptionRow(
                        key: ValueKey<String>('kernel-option-${descriptor.id}'),
                        label: descriptor.displayName,
                        selected: selected,
                        busy:
                            switching && state.targetKernelId == descriptor.id,
                        onPressed: selected || switching
                            ? null
                            : () => onSelectKernel(descriptor.id),
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: 12),
              _SettingsGroup(
                key: const ValueKey<String>('settings-group-diagnostics'),
                surfaceKey: const ValueKey<String>(
                  'settings-group-diagnostics-surface',
                ),
                title: '诊断',
                children: <Widget>[
                  _SettingsInfoRow(
                    label: '播放状态',
                    value: _lifecycleLabel(state.lifecycle),
                  ),
                  _SettingsInfoRow(
                    label: '当前内核',
                    value: _activeKernelName(controller, state),
                  ),
                  if (state.fallbackHistory.isNotEmpty)
                    _SettingsInfoRow(
                      label: '降级记录',
                      value: state.fallbackHistory.join(' → '),
                    ),
                  if (state.lastKernelSwitchError != null)
                    _SettingsInfoRow(
                      key: const ValueKey<String>('kernel-switch-diagnostic'),
                      label: '最近切换',
                      value: state.lastKernelSwitchError!.message,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerGlassSurface extends StatelessWidget {
  const _PlayerGlassSurface({
    required this.surfaceKey,
    required this.borderRadius,
    required this.materialProgress,
    required this.child,
  });

  final Key surfaceKey;
  final BorderRadius borderRadius;
  final double materialProgress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool highContrast = MediaQuery.highContrastOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
          BoxShadow(
            color: Color(0x3D000000),
            offset: Offset(0, 30),
            blurRadius: 80,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: highContrast
            ? DecoratedBox(
                key: surfaceKey,
                decoration: BoxDecoration(
                  color: _opaqueGlass,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.50),
                  ),
                ),
                child: child,
              )
            : Stack(
                fit: StackFit.passthrough,
                children: <Widget>[
                  Positioned.fill(
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        1.63,
                        -0.572,
                        -0.058,
                        0,
                        0,
                        -0.17,
                        1.228,
                        -0.058,
                        0,
                        0,
                        -0.17,
                        -0.572,
                        1.742,
                        0,
                        0,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ]),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 20 * materialProgress,
                          sigmaY: 20 * materialProgress,
                        ),
                        child: const ColoredBox(color: Color(0xB31E1E22)),
                      ),
                    ),
                  ),
                  DecoratedBox(
                    key: surfaceKey,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: child,
                  ),
                ],
              ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.subtitle, required this.onClose});

  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(
          child: Text(
            '播放设置',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.32,
            ),
          ),
        ),
        Flexible(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.60),
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox.square(
          dimension: 44,
          child: IconButton(
            key: const ValueKey<String>('settings-close'),
            tooltip: '关闭播放设置',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    super.key,
    required this.surfaceKey,
    required this.title,
    required this.children,
  });

  final Key surfaceKey;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 0, 3, 6),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(PlayerViewTokens.groupRadius),
          child: DecoratedBox(
            key: surfaceKey,
            decoration: const BoxDecoration(
              color: PlayerViewTokens.neutralGroupSurface,
              borderRadius: BorderRadius.all(
                Radius.circular(PlayerViewTokens.groupRadius),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _withHairlines(children),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsOptionRow extends StatelessWidget {
  const _SettingsOptionRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.minimumHeight = 46,
    this.busy = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final double minimumHeight;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected
        ? _playerAccent
        : onPressed == null && !busy
        ? Colors.white.withValues(alpha: 0.54)
        : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onPressed != null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minimumHeight),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                  if (busy)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  else if (selected)
                    const Icon(
                      Icons.check_rounded,
                      color: _playerAccent,
                      size: 18,
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

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      toggled: value,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onChanged,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Switch(
                      value: value,
                      onChanged: (_) {},
                      activeTrackColor: _playerAccent,
                      activeThumbColor: Colors.white,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.20),
                      inactiveThumbColor: Colors.white,
                    ),
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

class _FitOptionsRow extends StatelessWidget {
  const _FitOptionsRow({required this.selectedFit, required this.onSelected});

  final UnifiedVideoFit selectedFit;
  final ValueChanged<UnifiedVideoFit> onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Row(
        children: UnifiedVideoFit.values
            .map((UnifiedVideoFit fit) {
              final bool selected = fit == selectedFit;
              return Expanded(
                child: Semantics(
                  key: ValueKey<String>('fit-option-${fit.name}'),
                  button: true,
                  selected: selected,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: () => onSelected(fit),
                      child: SizedBox(
                        height: 46,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                _fitLabel(fit),
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(
                                  color: selected
                                      ? _playerAccent
                                      : Colors.white,
                                  fontSize: 10,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(
                                Icons.check_rounded,
                                color: _playerAccent,
                                size: 14,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _RotationRow extends StatelessWidget {
  const _RotationRow({
    required this.quarterTurns,
    required this.onRotateLeft,
    required this.onRotateRight,
  });

  final int quarterTurns;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Padding(
        padding: const EdgeInsets.only(left: 11),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '旋转 ${quarterTurns * 90}°',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
            _SettingsIconAction(
              key: const ValueKey<String>('rotation-left'),
              tooltip: '向左旋转',
              icon: Icons.rotate_left_rounded,
              onPressed: onRotateLeft,
            ),
            _SettingsIconAction(
              key: const ValueKey<String>('rotation-right'),
              tooltip: '向右旋转',
              icon: Icons.rotate_right_rounded,
              onPressed: onRotateRight,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsIconAction extends StatelessWidget {
  const _SettingsIconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0x8FFFFFFF),
                  size: 19,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.56),
                  fontSize: 11,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> _withHairlines(List<Widget> children) {
  return <Widget>[
    for (int index = 0; index < children.length; index++) ...<Widget>[
      if (index > 0)
        Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withValues(alpha: 0.10),
        ),
      children[index],
    ],
  ];
}

String _speedLabel(double speed) {
  if (speed == speed.roundToDouble()) {
    return '${speed.toStringAsFixed(1)}×';
  }
  if (speed * 10 == (speed * 10).roundToDouble()) {
    return '${speed.toStringAsFixed(1)}×';
  }
  return '${speed.toStringAsFixed(2)}×';
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

String _lifecycleLabel(UnifiedVideoLifecycle lifecycle) {
  switch (lifecycle) {
    case UnifiedVideoLifecycle.idle:
      return '空闲';
    case UnifiedVideoLifecycle.opening:
      return '正在打开';
    case UnifiedVideoLifecycle.switchingKernel:
      return '正在切换内核';
    case UnifiedVideoLifecycle.ready:
      return '已就绪';
    case UnifiedVideoLifecycle.playing:
      return '播放中';
    case UnifiedVideoLifecycle.paused:
      return '已暂停';
    case UnifiedVideoLifecycle.buffering:
      return '正在缓冲';
    case UnifiedVideoLifecycle.ended:
      return '已结束';
    case UnifiedVideoLifecycle.failed:
      return '播放失败';
    case UnifiedVideoLifecycle.disposed:
      return '已释放';
  }
}
