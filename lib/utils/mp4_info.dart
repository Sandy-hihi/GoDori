import 'dart:typed_data';

/// MP4 영상 파일 정보 읽기 (관리자 웹에서 룰 영상을 올리기 전에 규격 검사용)
///
/// 파일 앞뒤의 상자(box) 구조만 읽음 — 영상을 풀지(디코딩) 않아서 빠름.
///   ftyp → MP4인지, moov가 mdat보다 앞인지(faststart, 내려받으면서 바로 재생)
///   moov/trak/mdia: hdlr(영상·소리 구분), mdhd(시간 단위·길이), stsd(코덱·가로세로), stts(프레임 수 → fps)
class Mp4Info {
  final bool isMp4;
  final bool faststart;
  final String? videoCodec; // avc1 / avc3 = H.264, hvc1 / hev1 = H.265
  final int? width;
  final int? height;
  final double? fps;
  final double? durationSec;
  final String? audioCodec; // mp4a = AAC

  const Mp4Info({
    required this.isMp4,
    this.faststart = false,
    this.videoCodec,
    this.width,
    this.height,
    this.fps,
    this.durationSec,
    this.audioCodec,
  });

  bool get isH264 => videoCodec == 'avc1' || videoCodec == 'avc3';

  /// "1920×1080 · 30fps · H.264 · 8분 0초"
  String get summary {
    final parts = <String>[
      if (width != null && height != null) '$width×$height',
      if (fps != null) '${fps!.toStringAsFixed(fps! % 1 == 0 ? 0 : 2)}fps',
      if (videoCodec != null) isH264 ? 'H.264' : videoCodec!,
      if (durationSec != null) '${durationSec! ~/ 60}분 ${(durationSec! % 60).round()}초',
    ];
    return parts.join(' · ');
  }

  static Mp4Info parse(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final top = <String>[];
    for (final b in _boxes(bd, 0, bytes.length)) {
      top.add(b.type);
    }
    final isMp4 = (top.isNotEmpty && top.first == 'ftyp') || top.contains('moov');
    if (!isMp4) return const Mp4Info(isMp4: false);
    final moovAt = top.indexOf('moov');
    final mdatAt = top.indexOf('mdat');
    final faststart = moovAt >= 0 && (mdatAt < 0 || moovAt < mdatAt);

    String? vCodec;
    String? aCodec;
    int? w;
    int? h;
    double? fps;
    double? dur;
    for (final moov in _boxes(bd, 0, bytes.length).where((b) => b.type == 'moov')) {
      for (final trak in _boxes(bd, moov.start, moov.end).where((b) => b.type == 'trak')) {
        final t = _readTrak(bd, trak);
        if (t.handler == 'vide' && vCodec == null) {
          vCodec = t.codec;
          w = t.width;
          h = t.height;
          if (t.timescale != null && t.timescale! > 0) {
            if (t.sampleDelta > 0) fps = t.samples * t.timescale! / t.sampleDelta;
            if (t.duration != null) dur = t.duration! / t.timescale!;
          }
        } else if (t.handler == 'soun' && aCodec == null) {
          aCodec = t.codec;
        }
      }
    }
    return Mp4Info(
      isMp4: true,
      faststart: faststart,
      videoCodec: vCodec,
      width: w,
      height: h,
      fps: fps,
      durationSec: dur,
      audioCodec: aCodec,
    );
  }
}

class _Box {
  final String type;
  final int start; // 내용 시작 (머리 다음)
  final int end;
  _Box(this.type, this.start, this.end);
}

class _Trak {
  String? handler;
  int? timescale;
  int? duration;
  String? codec;
  int? width;
  int? height;
  int samples = 0;
  int sampleDelta = 0;
}

String _fourcc(ByteData bd, int p) =>
    String.fromCharCodes([bd.getUint8(p), bd.getUint8(p + 1), bd.getUint8(p + 2), bd.getUint8(p + 3)]);

// 64비트 숫자 (웹에서는 getUint64가 안 돼서 32비트 두 개로)
int _u64(ByteData bd, int p) => bd.getUint32(p) * 4294967296 + bd.getUint32(p + 4);

Iterable<_Box> _boxes(ByteData bd, int start, int end) sync* {
  var p = start;
  while (p + 8 <= end) {
    var size = bd.getUint32(p);
    final type = _fourcc(bd, p + 4);
    var header = 8;
    if (size == 1) {
      if (p + 16 > end) return;
      size = _u64(bd, p + 8);
      header = 16;
    } else if (size == 0) {
      size = end - p; // 파일 끝까지
    }
    if (size < header) return;
    final boxEnd = p + size > end ? end : p + size;
    yield _Box(type, p + header, boxEnd);
    if (p + size > end) return; // 잘린 상자 (마지막 mdat 등)
    p += size;
  }
}

_Trak _readTrak(ByteData bd, _Box trak) {
  final t = _Trak();
  for (final mdia in _boxes(bd, trak.start, trak.end).where((b) => b.type == 'mdia')) {
    for (final b in _boxes(bd, mdia.start, mdia.end)) {
      if (b.type == 'hdlr' && b.start + 12 <= b.end) {
        t.handler = _fourcc(bd, b.start + 8);
      } else if (b.type == 'mdhd' && b.start + 20 <= b.end) {
        if (bd.getUint8(b.start) == 1) {
          if (b.start + 32 <= b.end) {
            t.timescale = bd.getUint32(b.start + 20);
            t.duration = _u64(bd, b.start + 24);
          }
        } else {
          t.timescale = bd.getUint32(b.start + 12);
          t.duration = bd.getUint32(b.start + 16);
        }
      } else if (b.type == 'minf') {
        for (final stbl in _boxes(bd, b.start, b.end).where((x) => x.type == 'stbl')) {
          for (final s in _boxes(bd, stbl.start, stbl.end)) {
            if (s.type == 'stsd' && s.start + 16 <= s.end) {
              final entry = s.start + 8;
              t.codec = _fourcc(bd, entry + 4);
              if (entry + 36 <= s.end) {
                t.width = bd.getUint16(entry + 32);
                t.height = bd.getUint16(entry + 34);
              }
            } else if (s.type == 'stts' && s.start + 8 <= s.end) {
              final n = bd.getUint32(s.start + 4);
              for (var i = 0; i < n; i++) {
                final at = s.start + 8 + i * 8;
                if (at + 8 > s.end) break;
                final count = bd.getUint32(at);
                t.samples += count;
                t.sampleDelta += count * bd.getUint32(at + 4);
              }
            }
          }
        }
      }
    }
  }
  return t;
}

/// 룰 영상 규격 검사 결과
class RuleVideoCheck {
  final List<String> errors; // 올릴 수 없음
  final List<String> warnings; // 올릴 수는 있지만 확인 필요
  RuleVideoCheck(this.errors, this.warnings);
  bool get ok => errors.isEmpty;
}

/// 41차 규격: 1080p 30fps H.264 + AAC MP4 (faststart). quality: '1080' 또는 '720'
/// 패드(Teclast P20HD, Unisoc SC9863A)는 1080p 30fps까지만 하드웨어로 풀 수 있어서 60fps·4K는 막음.
RuleVideoCheck checkRuleVideo(Mp4Info info, {required String quality, required int sizeBytes, required int maxBytes}) {
  final errors = <String>[];
  final warnings = <String>[];
  if (!info.isMp4) {
    errors.add('MP4 영상이 아니에요. HandBrake로 MP4(H.264)로 만들어 주세요.');
    return RuleVideoCheck(errors, warnings);
  }
  if (sizeBytes > maxBytes) {
    errors.add('영상이 너무 커요 (${(sizeBytes / 1048576).toStringAsFixed(0)}MB). ${maxBytes ~/ 1048576}MB 이하로 만들어 주세요.');
  }
  if (info.videoCodec == null) {
    errors.add('영상 트랙을 찾지 못했어요.');
  } else if (!info.isH264) {
    errors.add('H.264 영상만 올릴 수 있어요 (지금: ${info.videoCodec}). HandBrake 동영상 코덱을 H.264로 해 주세요.');
  }
  final fps = info.fps;
  if (fps != null && fps > 31) {
    errors.add('${fps.round()}fps 영상은 매장 패드에서 끊겨요. 30fps로 만들어 주세요.');
  }
  final w = info.width ?? 0;
  final h = info.height ?? 0;
  final long = w > h ? w : h;
  final short = w > h ? h : w;
  if (long > 1920 || short > 1080) {
    errors.add('$w×$h 영상은 너무 커요. 1920×1080 이하로 만들어 주세요.');
  } else if (quality == '720' && (long > 1280 || short > 720)) {
    errors.add('720p 칸에는 1280×720 이하 영상을 올려 주세요 (지금 $w×$h).');
  } else if (quality == '1080' && short > 0 && short < 1080) {
    warnings.add('1080p 칸인데 영상이 $w×$h예요. 그대로 올릴까요?');
  }
  if (h > w && w > 0) warnings.add('세로 영상이에요. 룰 영상은 가로로 만들기로 했어요.');
  if (!info.faststart) {
    warnings.add('Web Optimized(faststart)가 꺼진 영상이에요. 재생 시작이 조금 늦을 수 있어요. (HandBrake "Web Optimized" 체크)');
  }
  if (info.audioCodec == null) {
    warnings.add('소리가 없는 영상이에요.');
  } else if (info.audioCodec != 'mp4a') {
    warnings.add('소리 형식이 AAC가 아니에요 (${info.audioCodec}). 소리가 안 나올 수 있어요.');
  }
  return RuleVideoCheck(errors, warnings);
}
