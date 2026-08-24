import 'models.dart';

enum PlaybackScenarioKind { mp4Vod, hlsVod, hlsLive, dashVod, invalidUrl }

class PlaybackScenario {
  const PlaybackScenario({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.source,
    required this.preferredKernelIds,
    required this.expectedResult,
    this.notes = const <String>[],
  });

  final String id;
  final PlaybackScenarioKind kind;
  final String title;
  final String description;
  final VideoSource source;
  final List<String> preferredKernelIds;
  final String expectedResult;
  final List<String> notes;
}

const String sampleAssetVideoPath = 'assets/videos/demo_tone.mp4';
const String sampleMp4Url = 'https://media.w3.org/2010/05/bunny/trailer.mp4';
const String sampleShortMp4Url =
    'https://media.w3.org/2010/05/video/movie_300.mp4';
const String sampleHlsVodUrl =
    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
const String sampleHlsLiveUrl =
    'https://cph-p2p-msl.akamaized.net/hls/live/2000341/test/master.m3u8';
const String sampleDashVodUrl =
    'https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd';
const String sampleInvalidUrl = 'https://example.invalid/video-missing.mp4';

const List<String> defaultNetworkKernelOrder = <String>[
  'video-player',
  'fvp',
  'media-kit',
];

const List<String> dashKernelOrder = <String>['media-kit', 'fvp'];

final List<PlaybackScenario> defaultPlaybackScenarios = <PlaybackScenario>[
  PlaybackScenario(
    id: 'local-asset-mp4',
    kind: PlaybackScenarioKind.mp4Vod,
    title: '本地 MP4 自检',
    description: '验证播放器无需外网也能显示画面、播放声音、刷新进度。',
    source: VideoSource.asset(
      sampleAssetVideoPath,
      metadata: const VideoMetadata(
        title: 'Local Demo Tone',
        episodeTitle: '本地自检',
      ),
    ),
    preferredKernelIds: defaultNetworkKernelOrder,
    expectedResult: '应自动播放 5 秒测试图和提示音，进度条持续更新。',
    notes: const <String>['如果该场景也不能播放，优先排查内核初始化、状态同步或平台音视频能力。'],
  ),
  PlaybackScenario(
    id: 'mp4-vod',
    kind: PlaybackScenarioKind.mp4Vod,
    title: 'MP4 点播',
    description: '验证普通网络 MP4 播放、暂停、进度拖动、上一集/下一集和切换内容。',
    source: VideoSource.network(
      sampleMp4Url,
      metadata: const VideoMetadata(
        title: 'Big Buck Bunny',
        episodeTitle: 'MP4 点播',
      ),
    ),
    preferredKernelIds: defaultNetworkKernelOrder,
    expectedResult: '应能打开并显示首帧，支持播放、暂停、seek、倍速和缩放。',
    notes: const <String>['官方 video_player、FVP 和 Media Kit 都应覆盖该场景。'],
  ),
  PlaybackScenario(
    id: 'mp4-short',
    kind: PlaybackScenarioKind.mp4Vod,
    title: '短 MP4 切集',
    description: '验证上一集、下一集、切换内容按钮在不同视频源之间复用同一控制器。',
    source: VideoSource.network(
      sampleShortMp4Url,
      metadata: const VideoMetadata(
        title: 'For Bigger Blazes',
        episodeTitle: '短 MP4',
      ),
    ),
    preferredKernelIds: defaultNetworkKernelOrder,
    expectedResult: '应能从当前视频切换到短视频，并保持统一 UI 控件可用。',
  ),
  PlaybackScenario(
    id: 'hls-vod',
    kind: PlaybackScenarioKind.hlsVod,
    title: 'HLS 点播',
    description: '验证 m3u8 点播流、缓冲状态、seek 和播放恢复。',
    source: VideoSource.network(
      sampleHlsVodUrl,
      metadata: const VideoMetadata(
        title: 'Mux HLS Test',
        episodeTitle: 'HLS 点播',
      ),
    ),
    preferredKernelIds: defaultNetworkKernelOrder,
    expectedResult: '应能打开 m3u8 清单并正常播放分片内容。',
    notes: const <String>['Windows 上优先用 Media Kit 或 FVP。'],
  ),
  PlaybackScenario(
    id: 'hls-live',
    kind: PlaybackScenarioKind.hlsLive,
    title: 'HLS 直播测试流',
    description: '验证直播式 m3u8 场景下播放、暂停、缓冲和进度条边界处理。',
    source: VideoSource.network(
      sampleHlsLiveUrl,
      metadata: const VideoMetadata(
        title: 'Akamai HLS Live Test',
        episodeTitle: 'HLS 直播',
      ),
    ),
    preferredKernelIds: defaultNetworkKernelOrder,
    expectedResult: '应能打开直播测试流；无固定总时长时 UI 不应崩溃。',
  ),
  PlaybackScenario(
    id: 'dash-vod',
    kind: PlaybackScenarioKind.dashVod,
    title: 'DASH 点播',
    description: '验证 mpd 自适应流，优先交给 Media Kit/libmpv 或 FVP/libmdk。',
    source: VideoSource.network(
      sampleDashVodUrl,
      metadata: const VideoMetadata(
        title: 'DASH Big Buck Bunny',
        episodeTitle: 'DASH 点播',
      ),
    ),
    preferredKernelIds: dashKernelOrder,
    expectedResult: '支持 DASH 的内核应能打开 mpd；不支持时应明确失败而不是静默黑屏。',
    notes: const <String>['官方 video_player 不作为 DASH 首选内核。'],
  ),
  PlaybackScenario(
    id: 'invalid-url',
    kind: PlaybackScenarioKind.invalidUrl,
    title: '错误地址',
    description: '验证无效播放地址的失败状态、错误提示和重试按钮。',
    source: VideoSource.network(
      sampleInvalidUrl,
      metadata: const VideoMetadata(
        title: 'Invalid Source',
        episodeTitle: '错误地址',
      ),
    ),
    preferredKernelIds: defaultNetworkKernelOrder,
    expectedResult: '应进入 failed 状态，显示错误提示和重试入口。',
  ),
];
