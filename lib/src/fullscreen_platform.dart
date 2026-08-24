import 'package:flutter/services.dart';

import 'models.dart';

class UnifiedVideoFullscreenPlatform {
  const UnifiedVideoFullscreenPlatform._();

  static const MethodChannel _channel = MethodChannel(
    'flutter_video/fullscreen',
  );

  static Future<void> enter(UnifiedVideoPlatform platform) async {
    switch (platform) {
      case UnifiedVideoPlatform.android:
      case UnifiedVideoPlatform.ios:
        await _ignoreUnavailablePlatform(
          () =>
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
        );
        await _ignoreUnavailablePlatform(
          () => SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]),
        );
      case UnifiedVideoPlatform.windows:
      case UnifiedVideoPlatform.macos:
      case UnifiedVideoPlatform.linux:
        await _invokeDesktop('enter');
      case UnifiedVideoPlatform.web:
      case UnifiedVideoPlatform.unknown:
        break;
    }
  }

  static Future<void> exit(UnifiedVideoPlatform platform) async {
    switch (platform) {
      case UnifiedVideoPlatform.android:
      case UnifiedVideoPlatform.ios:
        await _ignoreUnavailablePlatform(
          () => SystemChrome.setPreferredOrientations(
            const <DeviceOrientation>[],
          ),
        );
        await _ignoreUnavailablePlatform(
          () => SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          ),
        );
      case UnifiedVideoPlatform.windows:
      case UnifiedVideoPlatform.macos:
      case UnifiedVideoPlatform.linux:
        await _invokeDesktop('exit');
      case UnifiedVideoPlatform.web:
      case UnifiedVideoPlatform.unknown:
        break;
    }
  }

  static Future<void> _invokeDesktop(String method) async {
    await _ignoreUnavailablePlatform(() => _channel.invokeMethod<void>(method));
  }

  static Future<void> _ignoreUnavailablePlatform(
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on MissingPluginException {
      // 非桌面 runner、单元测试或尚未接入原生通道时保持状态机可用。
    } on PlatformException {
      // 平台通道异常不应让播放器状态卡死；真实端失败仍可通过日志定位。
    }
  }
}
