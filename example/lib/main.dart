import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lee_video_all/lee_video_all.dart';

VideoKernelRegistry createDemoKernelRegistry() {
  return VideoKernelRegistry(kernels: createAllVideoKernels());
}

void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '统一影视播放器示例',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const DemoHomePage(),
    );
  }
}

enum GSYDemoScene {
  single,
  listDetail,
  danmaku,
  filter,
  blurBackground,
  progressPreview,
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage>
    with SingleTickerProviderStateMixin {
  late final UnifiedVideoController _controller;
  late final AnimationController _animation;
  late GSYVideoPreviewProvider _previewProvider;

  int _sourceIndex = 0;
  GSYDemoScene _scene = GSYDemoScene.single;
  int _quarterTurns = 0;
  bool _mirrored = false;
  bool _smallWindow = false;
  bool _detailMode = false;
  bool _danmakuVisible = true;
  bool _warmFilter = false;
  bool _glAnimation = true;
  double _previewSeconds = 8;

  List<PlaybackScenario> get _sources => defaultPlaybackScenarios
      .where(
        (PlaybackScenario scenario) =>
            scenario.kind != PlaybackScenarioKind.invalidUrl,
      )
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _controller = UnifiedVideoController(
      registry: createDemoKernelRegistry(),
      preference: KernelPreference.ordered(
        _sources.first.preferredKernelIds,
        includeUnspecified: false,
      ),
    );
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
    _previewProvider = const GSYVideoPreviewVttParser().parse(
      _demoPreviewVtt,
      baseUri: Uri.parse(
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/',
      ),
    );
    unawaited(_openSource(_sourceIndex));
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('统一影视播放器 GSY 场景验证')),
      body: Stack(
        children: <Widget>[
          ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _buildPlayerStage(),
              const SizedBox(height: 16),
              _buildStateCard(),
              const SizedBox(height: 16),
              _buildSceneSelector(),
              const SizedBox(height: 16),
              _buildSceneControls(),
              const SizedBox(height: 16),
              _buildSourceList(),
            ],
          ),
          if (_smallWindow) _buildSmallWindow(context),
        ],
      ),
    );
  }

  Widget _buildPlayerStage() {
    if (_smallWindow) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text('小窗播放中', style: TextStyle(color: Colors.white70)),
          ),
        ),
      );
    }

    Widget player = UnifiedVideoPlayer(
      controller: _controller,
      onPrevious: _sourceIndex == 0 ? null : _previousSource,
      onNext: _sourceIndex == _sources.length - 1 ? null : _nextSource,
      onSwitchContent: _switchContent,
    );

    if (_scene == GSYDemoScene.single || _scene == GSYDemoScene.listDetail) {
      player = _RotatedMirroredPlayer(
        quarterTurns: _quarterTurns,
        mirrored: _mirrored,
        child: player,
      );
    }

    if (_scene == GSYDemoScene.filter) {
      player = _FilteredAnimatedPlayer(
        animation: _animation,
        warmFilter: _warmFilter,
        glAnimation: _glAnimation,
        child: player,
      );
    }

    if (_scene == GSYDemoScene.danmaku) {
      player = Stack(
        children: <Widget>[
          player,
          if (_danmakuVisible) _DanmakuOverlay(animation: _animation),
        ],
      );
    }

    if (_scene == GSYDemoScene.blurBackground) {
      player = _BlurBackgroundPlayer(child: player);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: KeyedSubtree(key: ValueKey<GSYDemoScene>(_scene), child: player),
    );
  }

  Widget _buildStateCard() {
    return ValueListenableBuilder<UnifiedVideoState>(
      valueListenable: _controller,
      builder: (BuildContext context, UnifiedVideoState state, Widget? child) {
        final PlaybackScenario source = _sources[_sourceIndex];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '当前验证：${_sceneLabel(_scene)} / ${source.title}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SelectableText('播放地址：${source.source.uri}'),
                Text('当前内核：${state.activeKernelId ?? '无'}'),
                Text('状态：${state.lifecycle.name}'),
                Text('旋转：${_quarterTurns * 90}°，镜像：${_mirrored ? '开' : '关'}'),
                Text('缩放：${state.fit.name}，倍速：${state.speed}x'),
                if (state.fallbackHistory.isNotEmpty)
                  Text('降级历史：${state.fallbackHistory.join(', ')}'),
                if (state.error != null)
                  Text(
                    '错误：${state.error!.backendMessage ?? state.error!.message}',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSceneSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('GSY 场景验证', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: GSYDemoScene.values
              .map((GSYDemoScene scene) {
                return ChoiceChip(
                  selected: _scene == scene,
                  label: Text(_sceneLabel(scene)),
                  onSelected: (_) {
                    setState(() {
                      _scene = scene;
                    });
                  },
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildSceneControls() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: Card(
        key: ValueKey<GSYDemoScene>(_scene),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _sceneLabel(_scene),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              switch (_scene) {
                GSYDemoScene.single => _buildSingleControls(),
                GSYDemoScene.listDetail => _buildListDetailControls(),
                GSYDemoScene.danmaku => _buildDanmakuControls(),
                GSYDemoScene.filter => _buildFilterControls(),
                GSYDemoScene.blurBackground => _buildBlurControls(),
                GSYDemoScene.progressPreview => _buildPreviewControls(),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSingleControls() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilledButton.icon(
          onPressed: _rotatePlayer,
          icon: const Icon(Icons.screen_rotation_alt),
          label: const Text('旋转 90°'),
        ),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              _mirrored = !_mirrored;
            });
          },
          icon: const Icon(Icons.flip),
          label: Text(_mirrored ? '关闭镜像' : '开启镜像'),
        ),
        FilledButton.icon(
          onPressed: () {
            unawaited(_controller.setFit(UnifiedVideoFit.fill));
          },
          icon: const Icon(Icons.fit_screen),
          label: const Text('填充'),
        ),
        FilledButton.icon(
          onPressed: () {
            unawaited(_controller.setFit(UnifiedVideoFit.cover));
          },
          icon: const Icon(Icons.crop_free),
          label: const Text('裁剪'),
        ),
      ],
    );
  }

  Widget _buildListDetailControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _detailMode = !_detailMode;
                });
              },
              icon: const Icon(Icons.animation),
              label: Text(_detailMode ? '返回列表' : '动画进入详情'),
            ),
            FilledButton.icon(
              onPressed: _rotatePlayer,
              icon: const Icon(Icons.screen_rotation_alt),
              label: const Text('详情旋转'),
            ),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _smallWindow = !_smallWindow;
                });
              },
              icon: const Icon(Icons.picture_in_picture_alt),
              label: Text(_smallWindow ? '关闭小窗体' : '开启小窗体'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _detailMode
              ? Text(
                  '详情模式：当前片源 ${_sources[_sourceIndex].title}，播放器支持动画切换、旋转和小窗体。',
                  key: const ValueKey<String>('detail-mode'),
                )
              : const Text(
                  '列表模式：点击下方片源卡片切换播放，或进入详情模式验证动画。',
                  key: ValueKey<String>('list-mode'),
                ),
        ),
      ],
    );
  }

  Widget _buildDanmakuControls() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilledButton.icon(
          onPressed: () {
            setState(() {
              _danmakuVisible = !_danmakuVisible;
            });
          },
          icon: const Icon(Icons.subtitles),
          label: Text(_danmakuVisible ? '关闭弹幕' : '开启弹幕'),
        ),
        const Chip(label: Text('弹幕覆盖层跟随播放器尺寸，不侵入内核')),
      ],
    );
  }

  Widget _buildFilterControls() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilledButton.icon(
          onPressed: () {
            setState(() {
              _warmFilter = !_warmFilter;
            });
          },
          icon: const Icon(Icons.filter),
          label: Text(_warmFilter ? '冷色滤镜' : '暖色滤镜'),
        ),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              _glAnimation = !_glAnimation;
            });
          },
          icon: const Icon(Icons.auto_awesome_motion),
          label: Text(_glAnimation ? '关闭 GL 动画' : '开启 GL 动画'),
        ),
      ],
    );
  }

  Widget _buildBlurControls() {
    return const Text('背景使用当前影视封面铺满并模糊，前景播放器保持可交互。');
  }

  Widget _buildPreviewControls() {
    return _VttPreviewScrubber(
      provider: _previewProvider,
      seconds: _previewSeconds,
      onChanged: (double value) {
        setState(() {
          _previewSeconds = value;
        });
      },
    );
  }

  Widget _buildSourceList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('播放源列表/详情验证', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ..._sources.indexed.map((entry) {
          final int index = entry.$1;
          final PlaybackScenario source = entry.$2;
          return Card(
            child: ListTile(
              selected: index == _sourceIndex,
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(source.title),
              subtitle: Text(source.source.uri.toString()),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: () {
                unawaited(_openSource(index));
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSmallWindow(BuildContext context) {
    final double width = math.min(MediaQuery.sizeOf(context).width - 32, 280);
    return Positioned(
      right: 16,
      bottom: 24,
      width: width,
      child: Material(
        elevation: 10,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: <Widget>[
            UnifiedVideoPlayer(controller: _controller, aspectRatio: 16 / 9),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filledTonal(
                onPressed: () {
                  setState(() {
                    _smallWindow = false;
                  });
                },
                icon: const Icon(Icons.close),
                tooltip: '关闭小窗体',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSource(int index) async {
    setState(() {
      _sourceIndex = index;
    });
    final PlaybackScenario source = _sources[index];
    try {
      await _controller.open(
        source.source,
        preference: KernelPreference.ordered(
          source.preferredKernelIds,
          includeUnspecified: false,
        ),
      );
      await _controller.play();
    } catch (_) {
      // 错误状态由播放器覆盖层展示。
    }
  }

  void _previousSource() {
    if (_sourceIndex == 0) {
      return;
    }
    unawaited(_openSource(_sourceIndex - 1));
  }

  void _nextSource() {
    if (_sourceIndex == _sources.length - 1) {
      return;
    }
    unawaited(_openSource(_sourceIndex + 1));
  }

  void _switchContent() {
    unawaited(_openSource((_sourceIndex + 1) % _sources.length));
  }

  void _rotatePlayer() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
    });
  }

  String _sceneLabel(GSYDemoScene scene) {
    return switch (scene) {
      GSYDemoScene.single => '1 打开播放：旋转/镜像/填充',
      GSYDemoScene.listDetail => '2 列表/详情：动画/旋转/小窗体',
      GSYDemoScene.danmaku => '3 弹幕',
      GSYDemoScene.filter => '4 滤镜和 GL 动画',
      GSYDemoScene.blurBackground => '6 背景铺满模糊播放',
      GSYDemoScene.progressPreview => '7 进度条小窗口预览',
    };
  }
}

class _RotatedMirroredPlayer extends StatelessWidget {
  const _RotatedMirroredPlayer({
    required this.quarterTurns,
    required this.mirrored,
    required this.child,
  });

  final int quarterTurns;
  final bool mirrored;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(mirrored ? -1.0 : 1.0, 1.0, 1.0),
      child: RotatedBox(quarterTurns: quarterTurns, child: child),
    );
  }
}

class _DanmakuOverlay extends StatelessWidget {
  const _DanmakuOverlay({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final List<String> comments = <String>[
      '统一 API 切内核',
      'HLS / DASH 验证',
      '倍速 0.5x - 3.0x',
      'GSY 场景弹幕',
    ];
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, Widget? child) {
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return Stack(
                children: comments.indexed
                    .map((entry) {
                      final int index = entry.$1;
                      final String text = entry.$2;
                      final double width = constraints.maxWidth + 180;
                      final double left =
                          width * ((animation.value + index * 0.23) % 1.0) -
                          180;
                      return Positioned(
                        left: left,
                        top: 24 + index * 34,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            child: Text(
                              text,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              );
            },
          );
        },
      ),
    );
  }
}

class _FilteredAnimatedPlayer extends StatelessWidget {
  const _FilteredAnimatedPlayer({
    required this.animation,
    required this.warmFilter,
    required this.glAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final bool warmFilter;
  final bool glAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget current = ColorFiltered(
      colorFilter: ColorFilter.mode(
        warmFilter
            ? Colors.orange.withValues(alpha: 0.22)
            : Colors.blue.withValues(alpha: 0.18),
        BlendMode.overlay,
      ),
      child: child,
    );
    if (!glAnimation) {
      return current;
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double wave = math.sin(animation.value * math.pi * 2);
        return Transform.scale(
          scale: 1 + wave.abs() * 0.015,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0007)
              ..rotateY(wave * 0.06),
            child: child,
          ),
        );
      },
      child: current,
    );
  }
}

class _BlurBackgroundPlayer extends StatelessWidget {
  const _BlurBackgroundPlayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Image.network(
              'https://commondatastorage.googleapis.com/gtv-videos-bucket/'
              'sample/images/BigBuckBunny.jpg',
              fit: BoxFit.cover,
            ),
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
          Padding(padding: const EdgeInsets.all(24), child: child),
        ],
      ),
    );
  }
}

class _VttPreviewScrubber extends StatelessWidget {
  const _VttPreviewScrubber({
    required this.provider,
    required this.seconds,
    required this.onChanged,
  });

  final GSYVideoPreviewProvider provider;
  final double seconds;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final Duration position = Duration(milliseconds: (seconds * 1000).round());
    final GSYVideoPreviewFrame? frame = provider.frameFor(position);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (frame != null)
          SizedBox(
            width: 220,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          frame.imageUri.toString(),
                          fit: BoxFit.cover,
                          errorBuilder:
                              (
                                BuildContext context,
                                Object error,
                                StackTrace? stackTrace,
                              ) {
                                return const ColoredBox(
                                  color: Colors.black54,
                                  child: Center(
                                    child: Icon(Icons.image_not_supported),
                                  ),
                                );
                              },
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_formatDuration(frame.start)} - ${_formatDuration(frame.end)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    if (frame.cropRect != null)
                      Text(
                        'xywh=${frame.cropRect!.left.toInt()},'
                        '${frame.cropRect!.top.toInt()},'
                        '${frame.cropRect!.width.toInt()},'
                        '${frame.cropRect!.height.toInt()}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Slider(
          key: const ValueKey<String>('vtt-preview-slider'),
          value: seconds,
          min: 0,
          max: 60,
          divisions: 60,
          label: _formatDuration(position),
          onChanged: onChanged,
        ),
        const Text(
          'WebVTT 预览：拖动时按时间命中 GSYVideoPreviewFrame，图片可以是独立缩略图或雪碧图 xywh。',
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

const String _demoPreviewVtt = '''
WEBVTT

00:00:00.000 --> 00:00:10.000
images/BigBuckBunny.jpg#xywh=0,0,284,160

00:00:10.000 --> 00:00:20.000
images/ElephantsDream.jpg#xywh=284,0,284,160

00:00:20.000 --> 00:00:40.000
images/ForBiggerBlazes.jpg#xywh=0,160,284,160

00:00:40.000 --> 00:01:00.000
images/Sintel.jpg#xywh=284,160,284,160
''';
