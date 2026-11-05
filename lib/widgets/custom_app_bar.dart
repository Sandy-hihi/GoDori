import 'package:flutter/material.dart';
import 'package:boardpad/widgets/store_brand.dart';
import 'dart:async';
import 'package:boardpad/services/staff_call_service.dart';
import 'package:boardpad/widgets/store_contact_label.dart';

class CustomAppBar extends StatefulWidget {
  final bool showBackButton;
  final bool showCallButton;
  final int? roomNumber;
  final Widget centerWidget;

  const CustomAppBar({
    super.key,
    this.showBackButton = false,
    this.showCallButton = false,
    this.roomNumber,
    required this.centerWidget,
  });

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();
}

class _CustomAppBarState extends State<CustomAppBar> {
  Timer? _logoutTimer;

  @override
  void dispose() {
    _logoutTimer?.cancel();
    super.dispose();
  }

  void _startLogoutTimer() {
    _logoutTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      // (지금은 안 쓰는 예전 상단 바) 첫 번째 라우트 = 홈 화면으로 이동.
      // 로그아웃은 홈 화면의 HoldToExit(home_common.dart)이 함
      Navigator.popUntil(context, (route) => route.isFirst);
    });
  }

  void _cancelLogoutTimer() {
    _logoutTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF00B37E),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        children: [
          if (widget.showBackButton)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          const StoreLogo(size: 40, padding: EdgeInsets.only(right: 16)),
          Expanded(flex: 2, child: widget.centerWidget),
          const SizedBox(width: 16),
          if (widget.showCallButton)
            ElevatedButton.icon(
              onPressed: () => StaffCallService.callStaff(context, widget.roomNumber ?? 0),
              icon: const Icon(Icons.notifications_active),
              label: const Text('직원 호출', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007E5B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          const Spacer(),
          GestureDetector(
            onTapDown: (_) => _startLogoutTimer(),
            onTapUp: (_) => _cancelLogoutTimer(),
            onTapCancel: () => _cancelLogoutTimer(),
            child: Container(
              color: Colors.transparent,
              // 매장 이름·전화번호가 비어도 10번 누르기(나가기) 자리는 남김
              constraints: const BoxConstraints(minWidth: 120, minHeight: 40),
              child: const StoreContactLabel(),
            ),
          ),
        ],
      ),
    );
  }
}
