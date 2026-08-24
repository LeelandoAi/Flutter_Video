import 'package:flutter/foundation.dart';

enum VideoSourceType { file, network, asset, memory }

enum UnifiedVideoLifecycle {
  idle,
  opening,
  switchingKernel,
  ready,
  playing,
  paused,
  buffering,
  ended,
  failed,
  disposed,
}

enum UnifiedVideoPlatform { android, ios, windows, macos, web, linux, unknown }

enum UnifiedVideoFit { original, ratio16x9, ratio4x3, contain, fill, cover }

enum UnifiedVideoErrorCode {
  unsupportedKernel,
  unsupportedCapability,
  openFailed,
  commandFailed,
  kernelSwitchFailed,
  runtimeConflict,
  disposedController,
}

enum VideoTrackType { video, audio, subtitle }

const List<double> unifiedVideoSpeedPresets = <double>[
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
  3.0,
];

UnifiedVideoPlatform currentUnifiedVideoPlatform() {
  if (kIsWeb) {
    return UnifiedVideoPlatform.web;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return UnifiedVideoPlatform.android;
    case TargetPlatform.iOS:
      return UnifiedVideoPlatform.ios;
    case TargetPlatform.macOS:
      return UnifiedVideoPlatform.macos;
    case TargetPlatform.windows:
      return UnifiedVideoPlatform.windows;
    case TargetPlatform.linux:
      return UnifiedVideoPlatform.linux;
    case TargetPlatform.fuchsia:
      return UnifiedVideoPlatform.unknown;
  }
}

class VideoSource {
  const VideoSource({
    required this.uri,
    required this.type,
    this.headers = const <String, String>{},
    this.metadata = const VideoMetadata(),
  });

  final Uri uri;
  final VideoSourceType type;
  final Map<String, String> headers;
  final VideoMetadata metadata;

  factory VideoSource.network(
    String url, {
    Map<String, String> headers = const <String, String>{},
    VideoMetadata metadata = const VideoMetadata(),
  }) {
    return VideoSource(
      uri: Uri.parse(url),
      type: VideoSourceType.network,
      headers: headers,
      metadata: metadata,
    );
  }

  factory VideoSource.asset(
    String assetName, {
    VideoMetadata metadata = const VideoMetadata(),
  }) {
    return VideoSource(
      uri: Uri(path: assetName),
      type: VideoSourceType.asset,
      metadata: metadata,
    );
  }

  factory VideoSource.file(
    String path, {
    VideoMetadata metadata = const VideoMetadata(),
  }) {
    return VideoSource(
      uri: Uri.file(path),
      type: VideoSourceType.file,
      metadata: metadata,
    );
  }
}

class VideoMetadata {
  const VideoMetadata({
    this.title,
    this.episodeTitle,
    this.extra = const <String, Object?>{},
  });

  final String? title;
  final String? episodeTitle;
  final Map<String, Object?> extra;
}

class BufferedRange {
  const BufferedRange({required this.start, required this.end});

  final Duration start;
  final Duration end;
}

class VideoTrack {
  const VideoTrack({
    required this.id,
    required this.type,
    required this.label,
    this.language,
    this.selected = false,
  });

  final String id;
  final VideoTrackType type;
  final String label;
  final String? language;
  final bool selected;
}

class UnifiedVideoError {
  const UnifiedVideoError({
    required this.code,
    required this.message,
    this.backendMessage,
    this.diagnostics = const <String, Object?>{},
  });

  final UnifiedVideoErrorCode code;
  final String message;
  final String? backendMessage;
  final Map<String, Object?> diagnostics;
}

class UnifiedVideoState {
  const UnifiedVideoState({
    this.lifecycle = UnifiedVideoLifecycle.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = const <BufferedRange>[],
    this.source,
    this.activeKernelId,
    this.fit = UnifiedVideoFit.contain,
    this.speed = 1.0,
    this.volume = 1.0,
    this.fullscreen = false,
    this.tracks = const <VideoTrack>[],
    this.error,
    this.targetKernelId,
    this.lastKernelSwitchError,
    this.fallbackHistory = const <String>[],
  });

  final UnifiedVideoLifecycle lifecycle;
  final Duration position;
  final Duration duration;
  final List<BufferedRange> buffered;
  final VideoSource? source;
  final String? activeKernelId;
  final UnifiedVideoFit fit;
  final double speed;
  final double volume;
  final bool fullscreen;
  final List<VideoTrack> tracks;
  final UnifiedVideoError? error;
  final String? targetKernelId;
  final UnifiedVideoError? lastKernelSwitchError;
  final List<String> fallbackHistory;

  bool get isPlaying => lifecycle == UnifiedVideoLifecycle.playing;
  bool get isDisposed => lifecycle == UnifiedVideoLifecycle.disposed;

  UnifiedVideoState copyWith({
    UnifiedVideoLifecycle? lifecycle,
    Duration? position,
    Duration? duration,
    List<BufferedRange>? buffered,
    VideoSource? source,
    bool clearSource = false,
    String? activeKernelId,
    bool clearActiveKernelId = false,
    UnifiedVideoFit? fit,
    double? speed,
    double? volume,
    bool? fullscreen,
    List<VideoTrack>? tracks,
    UnifiedVideoError? error,
    bool clearError = false,
    String? targetKernelId,
    bool clearTargetKernelId = false,
    UnifiedVideoError? lastKernelSwitchError,
    bool clearLastKernelSwitchError = false,
    List<String>? fallbackHistory,
  }) {
    return UnifiedVideoState(
      lifecycle: lifecycle ?? this.lifecycle,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffered: buffered ?? this.buffered,
      source: clearSource ? null : source ?? this.source,
      activeKernelId: clearActiveKernelId
          ? null
          : activeKernelId ?? this.activeKernelId,
      fit: fit ?? this.fit,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      fullscreen: fullscreen ?? this.fullscreen,
      tracks: tracks ?? this.tracks,
      error: clearError ? null : error ?? this.error,
      targetKernelId: clearTargetKernelId
          ? null
          : targetKernelId ?? this.targetKernelId,
      lastKernelSwitchError: clearLastKernelSwitchError
          ? null
          : lastKernelSwitchError ?? this.lastKernelSwitchError,
      fallbackHistory: fallbackHistory ?? this.fallbackHistory,
    );
  }
}
