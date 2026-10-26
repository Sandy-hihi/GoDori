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
      // 역할 선택 화면(RoleSelectionScreen)은 항상 첫 번째 라우트이므로
      // popUntil(isFirst)로 한 번에 이동
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
          StoreLogo(size: 40),
          const SizedBox(width: 16),
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
              child: const StoreContactLabel(),
            ),
          ),
        ],
      ),
    );
  }
}
