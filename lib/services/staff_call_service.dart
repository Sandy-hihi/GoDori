import 'package:boardpad/l10n/guest_language.dart';
import 'package:flutter/material.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/services/store_scope.dart';

class StaffCallService {
  static Future<void> callStaff(BuildContext context, int roomNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const GuestText('직원 호출', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const GuestText('직원을 호출하시겠습니까?', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const GuestText('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007E5B),
              foregroundColor: Colors.white,
            ),
            child: const GuestText('확인', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      try {
        await AdminSession.ensureSignedIn(); // 보안 규칙: 로그인한 그 방 패드만, 자기 방 번호로 호출 가능
        await StoreScope.col('staff_calls').add({
          'roomNumber': roomNumber,
          'timestamp': FieldValue.serverTimestamp(),
          'isAcknowledged': false,
        });
      } catch (e) {
        messenger?.showSnackBar(SnackBar(
          content: GuestText(e is AdminLoginException ? e.message : '직원 호출을 보내지 못했어요. 인터넷 연결을 확인해 주세요.'),
        ));
      }
    }
  }
}
