import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class UnifiedVideoFullscreenPlatform {
  const UnifiedVideoFullscreenPlatform._();

  static const MethodChannel _channel = MethodChannel(
    'leelando_video/fullscreen',
  );
  static final ValueNotifier<bool?> changes = ValueNotifier<bool?>(null);
  static bool _changeHandlerInitialized = false;
  static Object? _fullscreenOwner;

  static void claimFullscreenOwnership(Object owner) {
    _fullscreenOwner = owner;
  }

  static void claimFullscreenOwnershipIfUnclaimed(Object owner) {
    _fullscreenOwner ??= owner;
  }

  static void releaseFullscreenOwnership(Object owner) {
    if (identical(_fullscreenOwner, owner)) {
      _fullscreenOwner = null;
    }
  }

  static bool isFullscreenOwner(Object owner) {
    return identical(_fullscreenOwner, owner);
  }

  static void ensureChangeHandlerInitialized() {
    if (_changeHandlerInitialized) {
      return;
    }
    _changeHandlerInitialized = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'fullscreenChanged') {
        return;
      }
      final Object? arguments = call.arguments;
      if (arguments is Map && arguments['fullscreen'] is bool) {
        changes.value = arguments['fullscreen'] as bool;
      }
    });
  }

  static Future<void> enter(
    UnifiedVideoPlatform platform,
    UnifiedVideoFullscreenOrientation orientation,
  ) async {
    switch (platform) {
      case UnifiedVideoPlatform.android:
      case UnifiedVideoPlatform.ios:
        await _ignoreUnavailablePlatform(
          () =>
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
        );
        await _ignoreUnavailablePlatform(
          () => SystemChrome.setPreferredOrientations(
            _deviceOrientations(orientation),
          ),
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

  static List<DeviceOrientation> _deviceOrientations(
    UnifiedVideoFullscreenOrientation orientation,
  ) {
    return switch (orientation) {
      UnifiedVideoFullscreenOrientation.landscape => const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      UnifiedVideoFullscreenOrientation.portrait => const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ],
      UnifiedVideoFullscreenOrientation.auto => const <DeviceOrientation>[],
    };
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
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // 单元测试或 runner 尚未接入原生通道时保持状态机可用。
    }
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
