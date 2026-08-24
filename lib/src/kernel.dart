import 'package:flutter/widgets.dart';

import 'models.dart';

class VideoKernelDescriptor {
  const VideoKernelDescriptor({
    required this.id,
    required this.displayName,
    required this.supportedPlatforms,
    required this.supportedSourceTypes,
    this.supportsSurfaceRendering = true,
    this.supportsSubtitles = false,
    this.supportsTracks = false,
    this.supportedSpeeds = unifiedVideoSpeedPresets,
    this.supportedFits = UnifiedVideoFit.values,
    this.knownLimitations = const <String>[],
  });

  final String id;
  final String displayName;
  final Set<UnifiedVideoPlatform> supportedPlatforms;
  final Set<VideoSourceType> supportedSourceTypes;
  final bool supportsSurfaceRendering;
  final bool supportsSubtitles;
  final bool supportsTracks;
  final List<double> supportedSpeeds;
  final List<UnifiedVideoFit> supportedFits;
  final List<String> knownLimitations;

  bool supports(UnifiedVideoPlatform platform, VideoSource source) {
    return supportedPlatforms.contains(platform) &&
        supportedSourceTypes.contains(source.type);
  }

  bool supportsSpeed(double speed) {
    return supportedSpeeds.contains(speed);
  }

  bool supportsFit(UnifiedVideoFit fit) {
    return supportedFits.contains(fit);
  }
}

class KernelPreference {
  const KernelPreference.automatic()
    : preferredKernelIds = const <String>[],
      allowRuntimeFallback = true,
      includeUnspecified = true;

  factory KernelPreference.exact(String kernelId) {
    return KernelPreference.ordered(
      <String>[kernelId],
      allowRuntimeFallback: false,
      includeUnspecified: false,
    );
  }

  const KernelPreference.ordered(
    this.preferredKernelIds, {
    this.allowRuntimeFallback = true,
    this.includeUnspecified = true,
  });

  final List<String> preferredKernelIds;
  final bool allowRuntimeFallback;
  final bool includeUnspecified;
}

class KernelSelection {
  const KernelSelection({
    required this.adapter,
    required this.skippedKernelIds,
  });

  final VideoKernelAdapter adapter;
  final List<String> skippedKernelIds;
}

abstract class VideoKernelAdapter {
  VideoKernelDescriptor get descriptor;

  String? get runtimeGroup => null;

  String get runtimeIdentity => descriptor.id;

  Future<void> activateRuntime() async {}

  Future<void> deactivateRuntime() async {}

  Future<void> initialize();

  Future<UnifiedVideoState> open(VideoSource source, UnifiedVideoState state);

  Future<UnifiedVideoState> snapshot(UnifiedVideoState state);

  Future<UnifiedVideoState> play(UnifiedVideoState state);

  Future<UnifiedVideoState> pause(UnifiedVideoState state);

  Future<UnifiedVideoState> seek(Duration position, UnifiedVideoState state);

  Future<UnifiedVideoState> stop(UnifiedVideoState state);

  Future<UnifiedVideoState> setSpeed(double speed, UnifiedVideoState state);

  Future<UnifiedVideoState> setFit(
    UnifiedVideoFit fit,
    UnifiedVideoState state,
  );

  Future<UnifiedVideoState> setVolume(
    double volume,
    UnifiedVideoState state,
  ) async => state.copyWith(volume: volume);

  Widget buildSurface(BuildContext context, UnifiedVideoState state);

  Future<void> dispose();
}

typedef VideoKernelFactory = VideoKernelAdapter Function();

class RegisteredVideoKernel {
  const RegisteredVideoKernel({required this.descriptor, required this.create});

  final VideoKernelDescriptor descriptor;
  final VideoKernelFactory create;
}

class VideoKernelRegistry {
  VideoKernelRegistry({
    Iterable<RegisteredVideoKernel> kernels = const <RegisteredVideoKernel>[],
  }) {
    for (final RegisteredVideoKernel kernel in kernels) {
      register(kernel);
    }
  }

  final Map<String, RegisteredVideoKernel> _kernels =
      <String, RegisteredVideoKernel>{};

  List<VideoKernelDescriptor> get descriptors {
    return _kernels.values
        .map((RegisteredVideoKernel kernel) => kernel.descriptor)
        .toList(growable: false);
  }

  RegisteredVideoKernel? byId(String id) => _kernels[id];

  bool contains(String id) => _kernels.containsKey(id);

  void register(RegisteredVideoKernel kernel) {
    final String id = kernel.descriptor.id;
    if (_kernels.containsKey(id)) {
      throw DuplicateVideoKernelException(id);
    }
    _kernels[id] = kernel;
  }

  void registerAll(Iterable<RegisteredVideoKernel> kernels) {
    for (final RegisteredVideoKernel kernel in kernels) {
      register(kernel);
    }
  }

  RegisteredVideoKernel? unregister(String id) => _kernels.remove(id);

  List<RegisteredVideoKernel> orderedCandidates(KernelPreference preference) {
    if (preference.preferredKernelIds.isEmpty) {
      return _kernels.values.toList(growable: false);
    }

    final Iterable<RegisteredVideoKernel> preferred = preference
        .preferredKernelIds
        .map(byId)
        .whereType<RegisteredVideoKernel>();
    if (!preference.allowRuntimeFallback) {
      return preferred.toList(growable: false);
    }
    if (!preference.includeUnspecified) {
      return preferred.toList(growable: false);
    }

    return preferred
        .followedBy(
          _kernels.values.where(
            (RegisteredVideoKernel kernel) =>
                !preference.preferredKernelIds.contains(kernel.descriptor.id),
          ),
        )
        .toList(growable: false);
  }

  KernelSelection select({
    required UnifiedVideoPlatform platform,
    required VideoSource source,
    KernelPreference preference = const KernelPreference.automatic(),
  }) {
    final List<String> skipped = <String>[];
    for (final RegisteredVideoKernel kernel in orderedCandidates(preference)) {
      if (kernel.descriptor.supports(platform, source)) {
        return KernelSelection(
          adapter: kernel.create(),
          skippedKernelIds: skipped,
        );
      }
      skipped.add(kernel.descriptor.id);
    }

    throw UnsupportedKernelException(
      platform: platform,
      sourceType: source.type,
      candidateKernelIds: _kernels.keys.toList(growable: false),
      skippedKernelIds: skipped,
    );
  }
}

class DuplicateVideoKernelException implements Exception {
  const DuplicateVideoKernelException(this.kernelId);

  final String kernelId;

  @override
  String toString() => 'DuplicateVideoKernelException(内核 ID 已重复注册: $kernelId)';
}

class UnsupportedKernelException implements Exception {
  const UnsupportedKernelException({
    required this.platform,
    required this.sourceType,
    required this.candidateKernelIds,
    required this.skippedKernelIds,
  });

  final UnifiedVideoPlatform platform;
  final VideoSourceType sourceType;
  final List<String> candidateKernelIds;
  final List<String> skippedKernelIds;

  UnifiedVideoError toError() {
    return UnifiedVideoError(
      code: UnifiedVideoErrorCode.unsupportedKernel,
      message: '没有兼容当前平台和播放源的播放器内核。',
      diagnostics: <String, Object?>{
        'platform': platform.name,
        'sourceType': sourceType.name,
        'candidateKernelIds': candidateKernelIds,
        'skippedKernelIds': skippedKernelIds,
      },
    );
  }

  @override
  String toString() {
    return 'UnsupportedKernelException(platform: ${platform.name}, '
        'sourceType: ${sourceType.name}, candidates: $candidateKernelIds)';
  }
}
