import 'package:flutter/material.dart';
import 'package:boardpad/services/store_info_service.dart';

/// 상단 바 오른쪽의 매장 이름 + 전화번호 표시
class StoreContactLabel extends StatelessWidget {
  const StoreContactLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text('플랫폼6 보드카페', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        FutureBuilder<String>(
          future: StoreInfoService.phoneNumber(),
          builder: (context, snapshot) {
            final phone = snapshot.data ?? '';
            if (phone.isEmpty) return const SizedBox.shrink();
            return Text(phone, style: const TextStyle(color: Colors.white, fontSize: 12));
          },
        ),
      ],
    );
  }
}
