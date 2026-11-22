import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boardpad/l10n/guest_language.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/store_brand.dart';

/// 인터넷이 끊겼을 때 등 화면 전체 오류 (143차) — 손님 패드 색(크림 배경·흰 카드·주황)
///
/// - [network] true: 와이파이 그림 + '인터넷 연결이 끊겼어요' + 확인할 것 3줄 + [autoRetry]초마다 저절로 다시 시도(남은 초 표시)
/// - [network] false: 느낌표 그림 + '잠시 문제가 생겼어요' (저절로 다시 시도 안 함)
/// - [message]: 자세한 이유(서버가 준 문장 등) — 회색 작은 글씨
/// - [onRetry]: [다시 시도] 버튼·자동 재시도 때 부름. 도는 동안 버튼은 흐리게 + 다시 안 눌림(100차 규칙 — 글자는 그대로)
/// 모든 문구는 GuestText(손님 언어로 번역 — guest_messages.dart).
class NetworkErrorView extends StatefulWidget {
  final String message;
  final bool network;
  final Future<void> Function() onRetry;
  final int autoRetry; // 초 (0이면 안 함)

  const NetworkErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.network = true,
    this.autoRetry = 15,
  });

  @override
  State<NetworkErrorView> createState() => _NetworkErrorViewState();
}

class _NetworkErrorViewState extends State<NetworkErrorView> {
  Timer? _timer;
  int _left = 0;
  bool _busy = false;

  bool get _auto => widget.network && widget.autoRetry > 0;

  @override
  void initState() {
    super.initState();
    _restartCountdown();
  }

  void _restartCountdown() {
    _timer?.cancel();
    if (!_auto) return;
    _left = widget.autoRetry;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _busy) return;
      if (_left <= 1) {
        _retry();
      } else {
        setState(() => _left--);
      }
    });
  }

  Future<void> _retry() async {
    if (_busy) return;
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      await widget.onRetry();
    } finally {
      // 다시 실패해서 이 화면이 그대로면 카운트다운을 처음부터
      if (mounted) {
        setState(() => _busy = false);
        _restartCountdown();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.network ? '인터넷 연결이 끊겼어요' : '잠시 문제가 생겼어요';
    return Container(
      color: kBg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  padding: const EdgeInsets.fromLTRB(40, 44, 40, 36),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(color: kInk.withValues(alpha: 0.06), blurRadius: 30, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _picture(),
                      const SizedBox(height: 28),
                      GuestText(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kInk, height: 1.25),
                      ),
                      const SizedBox(height: 10),
                      GuestText(
                        widget.network ? '연결되면 바로 이어서 쓸 수 있어요.' : '잠시 후 다시 시도해 주세요.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 17, color: kBody, height: 1.45),
                      ),
                      if (widget.network) ...[
                        const SizedBox(height: 26),
                        _checks(),
                      ],
                      const SizedBox(height: 28),
                      _retryButton(),
                      if (_auto) ...[
                        const SizedBox(height: 14),
                        _countdown(),
                      ],
                      if (widget.message.trim().isNotEmpty) ...[
                        const SizedBox(height: 22),
                        GuestText(
                          widget.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: kMuted, height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Opacity(opacity: 0.55, child: GodoriBrand(size: 26, textColor: kMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 동그란 주황 바탕 + 와이파이(사선으로 그음) 또는 느낌표
  Widget _picture() {
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(color: kOrange.withValues(alpha: 0.1), shape: BoxShape.circle),
      child: Center(
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(color: kOrange.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: widget.network
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.wifi, size: 52, color: kOrange),
                    Transform.rotate(
                      angle: -0.8,
                      child: Container(
                        width: 66,
                        height: 6,
                        decoration: BoxDecoration(
                          color: kOrange,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xFFFBE6D6), width: 1.5),
                        ),
                      ),
                    ),
                  ],
                )
              : const Icon(Icons.error_outline_rounded, size: 52, color: kOrange),
        ),
      ),
    );
  }

  Widget _checks() {
    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 20, color: kInk),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: GuestText(text, style: const TextStyle(fontSize: 16, color: kInk, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          row(Icons.wifi, '와이파이가 켜져 있는지 확인해 주세요'),
          row(Icons.signal_cellular_alt, '공유기 전원과 선을 확인해 주세요'),
          row(Icons.person_outline, '계속 안 되면 직원에게 알려 주세요'),
        ],
      ),
    );
  }

  Widget _retryButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: FilledButton.icon(
        onPressed: _busy ? null : _retry,
        style: FilledButton.styleFrom(
          backgroundColor: kOrange,
          foregroundColor: Colors.white,
          disabledBackgroundColor: kOrange.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        icon: const Icon(Icons.refresh, size: 24),
        label: const GuestText('다시 시도', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _countdown() {
    final total = widget.autoRetry;
    final progress = _busy ? 1.0 : (total - _left) / total;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: kLine,
            color: kOrange,
          ),
        ),
        const SizedBox(height: 10),
        GuestText(
          _busy ? '연결하는 중이에요…' : '$_left초 뒤에 자동으로 다시 시도해요',
          style: const TextStyle(fontSize: 14, color: kMuted),
        ),
      ],
    );
  }
}
