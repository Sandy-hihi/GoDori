import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:boardpad/l10n/guest_language.dart';
import 'home_theme.dart';

/// 133차: 홈 격자 '와이파이' 위젯.
///   1×1 — options.view 'qr'(QR만 + 이름) 또는 'text'(이름·비밀번호 — 예전 모양, 기본값)
///   2×1 — 왼쪽 QR + 오른쪽 이름·비밀번호
/// QR은 이름·비밀번호로 패드가 직접 만듦(휴대폰 카메라로 찍으면 바로 연결). 사진을 올리지 않음.
/// options: ssid, password, security('WPA' 기본 | 'nopass'), hidden(bool), view('qr'|'text')
/// 손님 화면에서 이름이 비어 있으면 아무것도 안 그림(preview = 관리자 홈 꾸미기 미리보기면 안내 카드).
class WifiWidget extends StatelessWidget {
  const WifiWidget({super.key, required this.options, required this.wide, this.slim = false, this.preview = false});

  final Map<String, dynamic> options;
  final bool wide;

  /// 135차: 높이 0.5칸(2×0.5·3×0.5) — 이름·비밀번호 한 줄 (QR 없음)
  final bool slim;
  final bool preview;

  static const _accent = Color(0xFFB5751E);
  static const _sub = Color(0xFF8A7F70);

  String get _ssid => (options['ssid'] ?? '').toString().trim();
  String get _password => (options['password'] ?? '').toString().trim();
  bool get _open => options['security'] == 'nopass' || _password.isEmpty;
  bool get _qrView => options['view'] == 'qr';

  @override
  Widget build(BuildContext context) {
    if (_ssid.isEmpty) {
      if (!preview) return const SizedBox.shrink();
      if (slim) {
        return const HomeCard(
          color: Color(0xFFFFF8EC),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(Icons.wifi, color: _accent, size: 22),
            SizedBox(width: 8),
            Flexible(child: Text('와이파이 정보를 입력해 주세요', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: _sub))),
          ]),
        );
      }
      return const HomeCard(
        color: Color(0xFFFFF8EC),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi, color: _accent, size: 30),
            SizedBox(height: 8),
            Text('와이파이 정보를\n입력해 주세요',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _sub, height: 1.4)),
          ],
        ),
      );
    }
    final data = wifiQrData(
      ssid: _ssid,
      password: _password,
      security: _open ? 'nopass' : 'WPA',
      hidden: options['hidden'] == true,
    );
    final Widget card = slim ? _slimLine() : (wide ? _wide(data) : (_qrView ? _qrOnly(data) : _textOnly()));
    if (preview) return card;
    // 136차: 누르면 QR·이름·비밀번호를 크게 보여 주는 창
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showWifiDetails(context, ssid: _ssid, password: _password, open: _open, qrData: data),
      child: card,
    );
  }

  // 0.5칸: 📶 이름 | 비밀번호 ●●● (길면 작아짐)
  Widget _slimLine() {
    return HomeCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(color: Color(0xFFFFF1DC), shape: BoxShape.circle),
          child: const Icon(Icons.wifi, color: _accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
              Text(_ssid, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
              Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 12), color: const Color(0xFFE0D8CB)),
              if (_open)
                const GuestText('비밀번호 없음', style: TextStyle(fontSize: 15, color: _sub))
              else ...[
                const GuestText('비밀번호', style: TextStyle(fontSize: 13, color: _sub)),
                const SizedBox(width: 6),
                Text(_password,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk, letterSpacing: 0.3)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _qr(String data) => QrImageView(
        data: data,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: kInk),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: kInk),
      );

  Widget _label(String text) => Row(children: [
        const Icon(Icons.wifi, color: _accent, size: 16),
        const SizedBox(width: 5),
        Flexible(
          child: GuestText(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _accent)),
        ),
      ]);

  /// 길면 잘리지 않고 작아지는 한 줄 (비밀번호는 다 보여야 해서)
  Widget _fit(String text, TextStyle style) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, style: style),
      );

  Widget _password13(double size) => _open
      ? GuestText('비밀번호 없음', maxLines: 1, style: TextStyle(fontSize: size, color: _sub))
      : _fit(_password, TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: kInk, letterSpacing: 0.3));

  // 1×1 글자: 와이파이 이름·비밀번호 (예전 모양을 다듬음)
  Widget _textOnly() {
    return HomeCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _label('와이파이'),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _fit(_ssid, const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
            const SizedBox(height: 10),
            const GuestText('비밀번호', maxLines: 1, style: TextStyle(fontSize: 11, color: _sub)),
            const SizedBox(height: 2),
            _password13(15),
          ]),
        ],
      ),
    );
  }

  // 1×1 QR: QR + 아래 와이파이 이름
  Widget _qrOnly(String data) {
    return HomeCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          _label('와이파이'),
          const SizedBox(height: 6),
          Expanded(child: Center(child: AspectRatio(aspectRatio: 1, child: _qr(data)))),
          const SizedBox(height: 6),
          _fit(_ssid, const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
        ],
      ),
    );
  }

  // 2×1: 왼쪽 QR + 오른쪽 이름·비밀번호
  Widget _wide(String data) {
    return HomeCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEDE6DA)),
              ),
              child: _qr(data),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _label('와이파이'),
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _fit(_ssid, const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
                  const SizedBox(height: 8),
                  const GuestText('비밀번호', maxLines: 1, style: TextStyle(fontSize: 11, color: _sub)),
                  const SizedBox(height: 2),
                  _password13(16),
                ]),
                const GuestText('카메라로 찍으면 바로 연결돼요',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: _sub, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 와이파이 접속 QR 글 (WIFI:T:WPA;S:이름;P:비밀번호;H:true;;) — \ ; , : " 는 앞에 \ 를 붙임
String wifiQrData({required String ssid, String password = '', String security = 'WPA', bool hidden = false}) {
  String esc(String s) => s.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');
  final open = security == 'nopass' || password.isEmpty;
  final b = StringBuffer('WIFI:T:${open ? 'nopass' : 'WPA'};S:${esc(ssid)};');
  if (!open) b.write('P:${esc(password)};');
  if (hidden) b.write('H:true;');
  b.write(';');
  return b.toString();
}

/// 136차: 와이파이 위젯을 누르면 뜨는 창 — QR·와이파이 이름·비밀번호를 크게
Future<void> showWifiDetails(
  BuildContext context, {
  required String ssid,
  required String password,
  required bool open,
  required String qrData,
}) {
  const accent = Color(0xFFB5751E);
  const sub = Color(0xFF8A7F70);
  Widget big(String text, double size) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text,
            maxLines: 1,
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: kInk, letterSpacing: 0.3)),
      );
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => Dialog(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: Color(0xFFFFF1DC), shape: BoxShape.circle),
                  child: const Icon(Icons.wifi, color: accent),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: GuestText('와이파이', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  tooltip: guestTr(ctx, '닫기'),
                  icon: const Icon(Icons.close_rounded, color: sub),
                ),
              ]),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 260,
                    height: 260,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: QrImageView(
                      data: qrData,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: kInk),
                      dataModuleStyle:
                          const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: kInk),
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const GuestText('와이파이 이름', style: TextStyle(fontSize: 15, color: sub)),
                        const SizedBox(height: 4),
                        big(ssid, 34),
                        const SizedBox(height: 22),
                        const GuestText('비밀번호', style: TextStyle(fontSize: 15, color: sub)),
                        const SizedBox(height: 4),
                        if (open)
                          const GuestText('비밀번호 없음',
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: sub))
                        else
                          big(password, 34),
                        const SizedBox(height: 24),
                        Row(children: [
                          const Icon(Icons.qr_code_2, color: accent, size: 20),
                          const SizedBox(width: 6),
                          const Flexible(
                            child: GuestText('카메라로 찍으면 바로 연결돼요',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accent)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
