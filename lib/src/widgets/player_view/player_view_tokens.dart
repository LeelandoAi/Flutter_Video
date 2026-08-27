import 'package:flutter/widgets.dart';

import '../../models.dart';

enum PlayerViewMode { compact, expanded, wide }

class PlayerViewMetrics {
  const PlayerViewMetrics({
    required this.mode,
    required this.leftPadding,
    required this.rightPadding,
    required this.bottomPadding,
    required this.progressHeight,
    required this.iconSize,
    required this.primaryIconSize,
  });

  final PlayerViewMode mode;
  final double leftPadding;
  final double rightPadding;
  final double bottomPadding;
  final double progressHeight;
  final double iconSize;
  final double primaryIconSize;

  bool get showEpisodePicker => mode != PlayerViewMode.compact;
  bool get showMore => mode != PlayerViewMode.compact;

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
      mode = PlayerViewMode.expanded;
    } else if (desktop) {
      mode = width >= 640 ? PlayerViewMode.wide : PlayerViewMode.compact;
    } else if (orientation == Orientation.portrait || width < 480) {
      mode = PlayerViewMode.compact;
    } else {
      mode = PlayerViewMode.expanded;
    }

    switch (mode) {
      case PlayerViewMode.compact:
        return const PlayerViewMetrics(
          mode: PlayerViewMode.compact,
          leftPadding: 7,
          rightPadding: 7,
          bottomPadding: 1,
          progressHeight: 2,
          iconSize: 17,
          primaryIconSize: 23,
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
        );
    }
  }
}
