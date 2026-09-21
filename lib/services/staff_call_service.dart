import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StaffCallService {
  static Future<void> callStaff(BuildContext context, int roomNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('직원 호출', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('직원을 호출하시겠습니까?', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007E5B),
              foregroundColor: Colors.white,
            ),
            child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await FirebaseFirestore.instance.collection('staff_calls').add({
        'roomNumber': roomNumber,
        'timestamp': FieldValue.serverTimestamp(),
        'isAcknowledged': false,
      });
    }
  }
}
