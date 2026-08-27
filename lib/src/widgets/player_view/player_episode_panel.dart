import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models.dart';
import 'player_view_tokens.dart';

class PlayerEpisodePanel extends StatelessWidget {
  const PlayerEpisodePanel({
    super.key,
    required this.episodes,
    required this.activeEpisodeId,
    required this.mode,
    required this.openingEpisodeId,
    required this.onSelected,
    required this.onClose,
    this.materialProgress = 1,
  });

  final List<VideoEpisode> episodes;
  final String? activeEpisodeId;
  final PlayerViewMode mode;
  final String? openingEpisodeId;
  final ValueChanged<VideoEpisode> onSelected;
  final VoidCallback onClose;
  final double materialProgress;

  static const Color _accent = Color(0xFF7EC3FF);
  static const Color _opaqueGlass = Color(0xFF1E1E22);

  @override
  Widget build(BuildContext context) {
    final bool highContrast = MediaQuery.highContrastOf(context);
    final BorderRadius borderRadius = mode == PlayerViewMode.expanded
        ? const BorderRadius.horizontal(left: Radius.circular(22))
        : BorderRadius.circular(18);
    final Widget content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          mode == PlayerViewMode.expanded ? 16 : 14,
          mode == PlayerViewMode.expanded ? 20 : 14,
          mode == PlayerViewMode.expanded ? 16 : 14,
          mode == PlayerViewMode.expanded ? 18 : 14,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(3, 0, 3, 14),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '选集',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.32,
                      ),
                    ),
                  ),
                  Text(
                    '共 ${episodes.length} 集',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.60),
                      fontSize: 11,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  PlayerViewTokens.groupRadius,
                ),
                child: DecoratedBox(
                  key: const ValueKey<String>('episode-list-group-surface'),
                  decoration: const BoxDecoration(
                    color: PlayerViewTokens.neutralGroupSurface,
                    borderRadius: BorderRadius.all(
                      Radius.circular(PlayerViewTokens.groupRadius),
                    ),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: episodes.length,
                      separatorBuilder: (BuildContext context, int index) {
                        return Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.white.withValues(alpha: 0.10),
                        );
                      },
                      itemBuilder: (BuildContext context, int index) {
                        final VideoEpisode episode = episodes[index];
                        return _EpisodeRow(
                          episode: episode,
                          selected: episode.id == activeEpisodeId,
                          opening: episode.id == openingEpisodeId,
                          anotherEpisodeOpening:
                              openingEpisodeId != null &&
                              episode.id != openingEpisodeId,
                          onSelected: onSelected,
                          onClose: onClose,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      label: '选集，共 ${episodes.length} 集',
      child: DecoratedBox(
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
                  key: const ValueKey<String>('episode-panel-surface'),
                  decoration: BoxDecoration(
                    color: _opaqueGlass,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.50),
                    ),
                  ),
                  child: content,
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
                          child: ColoredBox(color: const Color(0xB31E1E22)),
                        ),
                      ),
                    ),
                    DecoratedBox(
                      key: const ValueKey<String>('episode-panel-surface'),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: content,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.selected,
    required this.opening,
    required this.anotherEpisodeOpening,
    required this.onSelected,
    required this.onClose,
  });

  final VideoEpisode episode;
  final bool selected;
  final bool opening;
  final bool anotherEpisodeOpening;
  final ValueChanged<VideoEpisode> onSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final bool enabled = selected || !anotherEpisodeOpening;
    final Color primaryColor = selected
        ? PlayerEpisodePanel._accent
        : Colors.white;
    final Color secondaryColor = selected
        ? PlayerEpisodePanel._accent
        : Colors.white.withValues(alpha: 0.55);
    final String subtitle = <String>[
      if (episode.subtitle case final String subtitle)
        if (subtitle.trim().isNotEmpty) subtitle,
      if (selected) '正在播放',
    ].join(' · ');
    final String semanticLabel = <String>[
      episode.title,
      if (episode.subtitle case final String subtitle)
        if (subtitle.trim().isNotEmpty) subtitle,
      if (selected) '正在播放',
    ].join('，');

    return InkWell(
      key: ValueKey<String>('episode-option-${episode.id}'),
      excludeFromSemantics: true,
      onTap: enabled
          ? () {
              if (selected) {
                onClose();
              } else {
                onSelected(episode);
              }
            }
          : null,
      child: Semantics(
        key: selected
            ? ValueKey<String>('episode-option-${episode.id}-selected')
            : null,
        button: true,
        enabled: enabled,
        selected: selected,
        label: semanticLabel,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 53),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          episode.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (opening)
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        color: PlayerEpisodePanel._accent,
                        strokeWidth: 1.8,
                      ),
                    )
                  else if (selected)
                    const Icon(
                      Icons.check_rounded,
                      color: PlayerEpisodePanel._accent,
                      size: 18,
                    )
                  else if (episode.duration case final Duration duration)
                    Text(
                      _formatEpisodeDuration(duration),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
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
      ),
    );
  }
}

String _formatEpisodeDuration(Duration duration) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    return '${duration.inHours}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
  }
  return '${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}';
}
