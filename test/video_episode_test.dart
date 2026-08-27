import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video/leelando_video.dart';

void main() {
  test('VideoEpisode 保留选集身份、名称和完整播放源', () {
    final VideoSource source = VideoSource.network(
      'https://example.com/e08.m3u8',
      headers: const <String, String>{'Authorization': 'Bearer token'},
      metadata: const VideoMetadata(episodeTitle: '雾港'),
    );
    final VideoEpisode episode = VideoEpisode(
      id: 'episode-8',
      title: '第 8 集',
      subtitle: '雾港',
      duration: const Duration(minutes: 48, seconds: 6),
      source: source,
      extra: const <String, Object?>{'season': 1},
    );

    expect(episode.id, 'episode-8');
    expect(episode.title, '第 8 集');
    expect(episode.subtitle, '雾港');
    expect(episode.duration, const Duration(minutes: 48, seconds: 6));
    expect(episode.source, same(source));
    expect(episode.source.headers['Authorization'], 'Bearer token');
    expect(episode.extra['season'], 1);
  });
}
