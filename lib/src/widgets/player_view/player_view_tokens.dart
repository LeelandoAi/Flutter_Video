import 'package:flutter/widgets.dart';

import '../../models.dart';

enum PlayerViewMode { compact, portraitFullscreen, expanded, wide }

abstract final class PlayerViewTokens {
  static const double desktopEmbeddedRadius = 18;
  static const double groupRadius = 12;
  static const Color neutralGroupSurface = Color(0x14FFFFFF);
}

class PlayerViewMetrics {
  const PlayerViewMetrics({
    required this.mode,
    required this.leftPadding,
    required this.rightPadding,
    required this.bottomPadding,
    required this.progressHeight,
    required this.iconSize,
    required this.primaryIconSize,
    required this.showMore,
  });

  final PlayerViewMode mode;
  final double leftPadding;
  final double rightPadding;
  final double bottomPadding;
  final double progressHeight;
  final double iconSize;
  final double primaryIconSize;
  final bool showMore;

  bool get showEpisodePicker => mode != PlayerViewMode.compact;

  factory PlayerViewMetrics.resolve({
    required UnifiedVideoPlatform platform,
    required bool fullscreen,
    required Orientation orientation,
    required double width,
    required EdgeInsets viewPadding,
  }) {
    final bool desktop =
        platform == UnifiedVideoPlatform.windows ||
        platform == UnifiedVideoPlatform.macos;
    final PlayerViewMode mode;
    if (fullscreen) {
      mode = !desktop && orientation == Orientation.portrait
          ? PlayerViewMode.portraitFullscreen
          : PlayerViewMode.expanded;
    } else if (desktop) {
      mode = width >= 640 ? PlayerViewMode.wide : PlayerViewMode.compact;
    } else if (orientation == Orientation.portrait || width < 480) {
      mode = PlayerViewMode.compact;
    } else {
      mode = PlayerViewMode.expanded;
    }

    switch (mode) {
      case PlayerViewMode.compact:
        return PlayerViewMetrics(
          mode: mode,
          leftPadding: 7,
          rightPadding: 7,
          bottomPadding: desktop ? 2 : 1,
          progressHeight: 2,
          iconSize: 17,
          primaryIconSize: 23,
          showMore: !desktop,
        );
      case PlayerViewMode.portraitFullscreen:
        return PlayerViewMetrics(
          mode: mode,
          leftPadding: viewPadding.left + 12,
          rightPadding: viewPadding.right + 12,
          bottomPadding: viewPadding.bottom,
          progressHeight: 3,
          iconSize: 19,
          primaryIconSize: 27,
          showMore: true,
        );
      case PlayerViewMode.expanded:
        return PlayerViewMetrics(
          mode: PlayerViewMode.expanded,
          leftPadding: viewPadding.left + 8,
          rightPadding: viewPadding.right + 24,
          bottomPadding: viewPadding.bottom,
          progressHeight: 3,
          iconSize: 21,
          primaryIconSize: 29,
          showMore: true,
        );
      case PlayerViewMode.wide:
        return const PlayerViewMetrics(
          mode: PlayerViewMode.wide,
          leftPadding: 14,
          rightPadding: 14,
          bottomPadding: 2,
          progressHeight: 3,
          iconSize: 21,
          primaryIconSize: 29,
          showMore: true,
        );
    }
  }
}
