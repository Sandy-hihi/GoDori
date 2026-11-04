import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/utils/mp4_info.dart';

// 테스트용 작은 MP4 만들기 (실제 파일과 같은 상자 구조, 영상 내용은 없음)
Uint8List _box(String type, List<int> payload) {
  final size = 8 + payload.length;
  return Uint8List.fromList([
    (size >> 24) & 0xff, (size >> 16) & 0xff, (size >> 8) & 0xff, size & 0xff,
    ...type.codeUnits,
    ...payload,
  ]);
}

List<int> _u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
List<int> _u16(int v) => [(v >> 8) & 0xff, v & 0xff];

Uint8List _trak({required String handler, required String codec, required int timescale, required int duration,
    int width = 0, int height = 0, int frames = 0, int delta = 0}) {
  final hdlr = _box('hdlr', [..._u32(0), ..._u32(0), ...handler.codeUnits, ...List.filled(12, 0), 0]);
  final mdhd = _box('mdhd', [..._u32(0), ..._u32(0), ..._u32(0), ..._u32(timescale), ..._u32(duration), 0, 0, 0, 0]);
  // 시각 샘플 항목: 크기·형식(8) + 예약 6 + 참조 2 + 미리정함 16 → 가로 2 · 세로 2
  final entry = _box(codec, [...List.filled(6, 0), ..._u16(1), ...List.filled(16, 0), ..._u16(width), ..._u16(height), ...List.filled(50, 0)]);
  final stsd = _box('stsd', [..._u32(0), ..._u32(1), ...entry]);
  final stts = _box('stts', [..._u32(0), ..._u32(1), ..._u32(frames), ..._u32(delta)]);
  final stbl = _box('stbl', [...stsd, ...stts]);
  final minf = _box('minf', stbl);
  final mdia = _box('mdia', [...mdhd, ...hdlr, ...minf]);
  return _box('trak', mdia);
}

Uint8List _mp4({required bool faststart, String codec = 'avc1', int w = 1920, int h = 1080, int fps = 30, bool audio = true}) {
  final ftyp = _box('ftyp', [...'isom'.codeUnits, ..._u32(512), ...'isomavc1'.codeUnits]);
  final video = _trak(handler: 'vide', codec: codec, timescale: fps * 512, duration: fps * 512 * 480, width: w, height: h, frames: fps * 480, delta: 512);
  final sound = _trak(handler: 'soun', codec: 'mp4a', timescale: 48000, duration: 48000 * 480);
  final moov = _box('moov', [...video, if (audio) ...sound]);
  final mdat = _box('mdat', List.filled(32, 0));
  return Uint8List.fromList(faststart ? [...ftyp, ...moov, ...mdat] : [...ftyp, ...mdat, ...moov]);
}

void main() {
  group('MP4 정보 읽기', () {
    test('1080p 30fps H.264 + AAC, faststart', () {
      final i = Mp4Info.parse(_mp4(faststart: true));
      expect(i.isMp4, isTrue);
      expect(i.faststart, isTrue);
      expect(i.isH264, isTrue);
      expect(i.width, 1920);
      expect(i.height, 1080);
      expect(i.fps, closeTo(30, 0.01));
      expect(i.durationSec, closeTo(480, 0.01));
      expect(i.audioCodec, 'mp4a');
      final c = checkRuleVideo(i, quality: '1080', sizeBytes: 250 << 20, maxBytes: 700 << 20);
      expect(c.ok, isTrue);
      expect(c.warnings, isEmpty);
    });

    test('60fps·H.265·4K는 막음, faststart 꺼짐은 경고', () {
      final i60 = Mp4Info.parse(_mp4(faststart: false, fps: 60));
      expect(i60.faststart, isFalse);
      final c60 = checkRuleVideo(i60, quality: '1080', sizeBytes: 1, maxBytes: 700 << 20);
      expect(c60.ok, isFalse);
      expect(c60.warnings.any((w) => w.contains('faststart')), isTrue);
      expect(checkRuleVideo(Mp4Info.parse(_mp4(faststart: true, codec: 'hvc1')), quality: '1080', sizeBytes: 1, maxBytes: 9).ok, isFalse);
      expect(checkRuleVideo(Mp4Info.parse(_mp4(faststart: true, w: 3840, h: 2160)), quality: '1080', sizeBytes: 1, maxBytes: 9).ok, isFalse);
    });

    test('720p 칸 검사, 용량 상한, MP4 아님', () {
      final hd = Mp4Info.parse(_mp4(faststart: true));
      expect(checkRuleVideo(hd, quality: '720', sizeBytes: 1, maxBytes: 9).ok, isFalse);
      final sd = Mp4Info.parse(_mp4(faststart: true, w: 1280, h: 720));
      expect(checkRuleVideo(sd, quality: '720', sizeBytes: 1, maxBytes: 9).ok, isTrue);
      expect(checkRuleVideo(sd, quality: '1080', sizeBytes: 1, maxBytes: 9).warnings, isNotEmpty);
      expect(checkRuleVideo(hd, quality: '1080', sizeBytes: 10, maxBytes: 9).ok, isFalse);
      expect(Mp4Info.parse(Uint8List.fromList(List.filled(100, 7))).isMp4, isFalse);
    });
  });
}
