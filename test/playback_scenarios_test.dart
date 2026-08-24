import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';

void main() {
  test('默认播放场景覆盖真实地址和异常地址验证', () {
    expect(defaultPlaybackScenarios, hasLength(greaterThanOrEqualTo(6)));

    final Set<PlaybackScenarioKind> kinds = defaultPlaybackScenarios
        .map((PlaybackScenario scenario) => scenario.kind)
        .toSet();
    expect(kinds, contains(PlaybackScenarioKind.mp4Vod));
    expect(kinds, contains(PlaybackScenarioKind.hlsVod));
    expect(kinds, contains(PlaybackScenarioKind.hlsLive));
    expect(kinds, contains(PlaybackScenarioKind.dashVod));
    expect(kinds, contains(PlaybackScenarioKind.invalidUrl));

    for (final PlaybackScenario scenario in defaultPlaybackScenarios) {
      expect(scenario.id, isNotEmpty);
      expect(scenario.title, isNotEmpty);
      expect(scenario.description, isNotEmpty);
      expect(scenario.expectedResult, isNotEmpty);
      expect(scenario.preferredKernelIds, isNotEmpty);

      if (scenario.source.type == VideoSourceType.network) {
        final String url = scenario.source.uri.toString();
        expect(url, startsWith('https://'));
        expect(url, isNot(contains('example.com')));
      } else {
        expect(scenario.source.type, VideoSourceType.asset);
        expect(scenario.source.uri.path, isNotEmpty);
      }
    }
  });

  test('DASH 场景不会把官方 video_player 作为首选内核', () {
    final PlaybackScenario dashScenario = defaultPlaybackScenarios.singleWhere(
      (PlaybackScenario scenario) =>
          scenario.kind == PlaybackScenarioKind.dashVod,
    );

    expect(dashScenario.source.uri.path, endsWith('.mpd'));
    expect(dashScenario.preferredKernelIds.take(2), <String>[
      'media-kit',
      'fvp',
    ]);
    expect(dashScenario.preferredKernelIds, isNot(contains('video-player')));
  });
}
