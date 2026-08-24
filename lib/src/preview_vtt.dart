import 'dart:ui';

class GSYVideoPreviewFrame {
  const GSYVideoPreviewFrame({
    required this.start,
    required this.end,
    required this.imageUri,
    this.cropRect,
  });

  final Duration start;
  final Duration end;
  final Uri imageUri;
  final Rect? cropRect;

  bool contains(Duration position) {
    return position >= start && position < end;
  }
}

class GSYVideoPreviewProvider {
  const GSYVideoPreviewProvider(this.frames);

  final List<GSYVideoPreviewFrame> frames;

  GSYVideoPreviewFrame? frameFor(Duration position) {
    for (final GSYVideoPreviewFrame frame in frames) {
      if (frame.contains(position)) {
        return frame;
      }
    }
    if (frames.isEmpty) {
      return null;
    }
    if (position >= frames.last.end) {
      return frames.last;
    }
    return null;
  }
}

class GSYVideoPreviewVttParser {
  const GSYVideoPreviewVttParser();

  GSYVideoPreviewProvider parse(String content, {Uri? baseUri}) {
    final List<String> lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final List<GSYVideoPreviewFrame> frames = <GSYVideoPreviewFrame>[];

    for (int index = 0; index < lines.length; index++) {
      final String line = lines[index].trim();
      if (line.isEmpty || line == 'WEBVTT' || line.startsWith('NOTE')) {
        continue;
      }

      if (!line.contains('-->')) {
        continue;
      }

      final List<String> range = line.split('-->');
      if (range.length != 2) {
        continue;
      }

      final Duration start = _parseTimestamp(range[0].trim());
      final Duration end = _parseTimestamp(range[1].trim());
      String imageLine = '';
      while (++index < lines.length) {
        imageLine = lines[index].trim();
        if (imageLine.isNotEmpty) {
          break;
        }
      }
      if (imageLine.isEmpty) {
        continue;
      }

      final _PreviewTarget target = _parseTarget(imageLine, baseUri: baseUri);
      frames.add(
        GSYVideoPreviewFrame(
          start: start,
          end: end,
          imageUri: target.imageUri,
          cropRect: target.cropRect,
        ),
      );
    }

    return GSYVideoPreviewProvider(
      List<GSYVideoPreviewFrame>.unmodifiable(frames),
    );
  }

  Duration _parseTimestamp(String value) {
    final List<String> parts = value.split(':');
    if (parts.length < 2 || parts.length > 3) {
      throw FormatException('非法 WebVTT 时间戳：$value');
    }

    final bool hasHours = parts.length == 3;
    final int hours = hasHours ? int.parse(parts[0]) : 0;
    final int minutes = int.parse(parts[hasHours ? 1 : 0]);
    final List<String> secondsParts = parts[hasHours ? 2 : 1].split('.');
    final int seconds = int.parse(secondsParts[0]);
    final int milliseconds = secondsParts.length > 1
        ? int.parse(secondsParts[1].padRight(3, '0').substring(0, 3))
        : 0;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  _PreviewTarget _parseTarget(String value, {Uri? baseUri}) {
    final int fragmentIndex = value.indexOf('#');
    final String rawUri = fragmentIndex == -1
        ? value
        : value.substring(0, fragmentIndex);
    final String? fragment = fragmentIndex == -1
        ? null
        : value.substring(fragmentIndex + 1);
    final Uri imageUri = baseUri == null
        ? Uri.parse(rawUri)
        : baseUri.resolve(rawUri);

    return _PreviewTarget(
      imageUri: imageUri,
      cropRect: fragment == null ? null : _parseCropRect(fragment),
    );
  }

  Rect? _parseCropRect(String fragment) {
    if (!fragment.startsWith('xywh=')) {
      return null;
    }
    final List<double> values = fragment
        .substring('xywh='.length)
        .split(',')
        .map(double.parse)
        .toList(growable: false);
    if (values.length != 4) {
      throw FormatException('非法 WebVTT xywh 坐标：$fragment');
    }
    return Rect.fromLTWH(values[0], values[1], values[2], values[3]);
  }
}

class _PreviewTarget {
  const _PreviewTarget({required this.imageUri, required this.cropRect});

  final Uri imageUri;
  final Rect? cropRect;
}
