import 'package:flutter/material.dart';

import 'ops_service.dart';

/// 운영자 페이지: 매장 카드의 '토스 POS 연결' 줄 (64차) — 서버 /api/ops/toss/*
///   가짜 포스(개발용, 키 없이): 매장의 고도리 메뉴로 만든 가짜 포스 상품에 주문이 들어감 → '가짜 포스 주문'에서 확인
///   실제 포스: 사장님이 토스 POS에 서비스 코드를 넣으면 토스가 '앱 설치' 웹훅을 보냄 → 설치 목록에서 골라 연결
class OpsTossRow extends StatelessWidget {
  final String storeId;
  final Map<String, dynamic>? overview; // GET /api/ops/toss/overview (아직 못 불러왔으면 null)
  final VoidCallback onChanged;
  const OpsTossRow({super.key, required this.storeId, required this.overview, required this.onChanged});

  Map<String, dynamic>? get _link {
    final links = overview?['links'];
    return links is Map && links[storeId] is Map ? Map<String, dynamic>.from(links[storeId] as Map) : null;
  }

  @override
  Widget build(BuildContext context) {
    if (overview == null) return const SizedBox.shrink();
    final link = _link;
    final text = link == null
        ? '포스 연결 안 됨'
        : link['mode'] == 'fake'
            ? '가짜 포스(개발용) · 메뉴 연결 ${link['mapped']}개'
            : '실제 포스: ${link['merchantName'] ?? ''} (가맹점 ${link['merchantId']}) · 메뉴 연결 ${link['mapped']}개'
                '${overview!['liveReady'] == true ? '' : ' · ⚠ 서버에 토스 키 없음'}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Icon(Icons.point_of_sale, size: 16, color: link == null ? Colors.black38 : const Color(0xFF3182F6)),
        Text(text, style: TextStyle(fontSize: 13, color: link == null ? Colors.black45 : Colors.black87)),
        TextButton(onPressed: () => _openLink(context), child: Text(link == null ? '포스 연결' : '연결 바꾸기')),
        if (link != null && link['mode'] == 'fake')
          TextButton(onPressed: () => _openFakeOrders(context), child: const Text('가짜 포스 주문')),
      ]),
    );
  }

  Future<void> _openLink(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _LinkDialog(storeId: storeId, overview: overview!, link: _link),
    );
    if (changed == true) onChanged();
  }

  Future<void> _openFakeOrders(BuildContext context) =>
      showDialog(context: context, builder: (_) => _FakeOrdersDialog(storeId: storeId));
}

class _LinkDialog extends StatefulWidget {
  final String storeId;
  final Map<String, dynamic> overview;
  final Map<String, dynamic>? link;
  const _LinkDialog({required this.storeId, required this.overview, required this.link});

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  bool _busy = false;
  String? _error;
  late bool _print = widget.link?['printOrderSheet'] == true;

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
      if (mounted) Navigator.pop(context, true);
    } on OpsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final installs = [
      for (final i in (widget.overview['installations'] as List? ?? const [])) Map<String, dynamic>.from(i as Map),
    ];
    final linkedId = '${widget.link?['merchantId'] ?? ''}';
    return AlertDialog(
      title: Text('${widget.storeId} — 토스 POS 연결'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('매장 카드의 \'토스 POS 연동\' 스위치도 켜져 있어야 주문이 포스로 가요.',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.science_outlined),
            title: const Text('가짜 포스(개발용)'),
            subtitle: const Text('토스 키 없이 시험. 이 매장 고도리 메뉴로 만든 가짜 포스 상품에 주문이 들어가요.'),
            trailing: linkedId == 'fake-${widget.storeId}' ? const Icon(Icons.check, color: Colors.green) : null,
            onTap: _busy ? null : () => _run(() => OpsService.tossLink(widget.storeId, 'fake')),
          ),
          const Divider(),
          Text('실제 포스 — 고도리 앱을 설치한 토스 가맹점 (${installs.length}곳)',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (widget.overview['webhookReady'] != true)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('서버에 토스 키·웹훅 비밀값이 아직 없어서 설치 소식을 받을 수 없어요. ("토스 POS 연결 방법.txt")',
                  style: TextStyle(color: Colors.orange, fontSize: 13)),
            ),
          for (final i in installs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_outlined),
              title: Text('${i['name'] ?? ''}  (가맹점 ${i['merchantId']})'),
              subtitle: Text('사업자 ${i['businessNumber'] ?? '-'}${i['removedAt'] != null ? '  · 앱 삭제됨' : ''}'),
              trailing: linkedId == '${i['merchantId']}' ? const Icon(Icons.check, color: Colors.green) : null,
              enabled: i['removedAt'] == null,
              onTap: _busy ? null : () => _run(() => OpsService.tossLink(widget.storeId, 'live', merchantId: '${i['merchantId']}')),
            ),
          if (widget.link != null) ...[
            const Divider(),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _print,
              title: const Text('포스에서 주문서 출력'),
              subtitle: const Text('패드 주문이 들어올 때 포스가 주문서를 뽑음'),
              onChanged: _busy
                  ? null
                  : (v) {
                      setState(() => _print = v == true);
                      _run(() => OpsService.tossConfig(widget.storeId, printOrderSheet: v == true));
                    },
            ),
          ],
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        ]),
      ),
      actions: [
        if (widget.link != null)
          TextButton(
            onPressed: _busy ? null : () => _run(() => OpsService.tossUnlink(widget.storeId)),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('연결 끊기'),
          ),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('닫기')),
      ],
    );
  }
}

class _FakeOrdersDialog extends StatefulWidget {
  final String storeId;
  const _FakeOrdersDialog({required this.storeId});

  @override
  State<_FakeOrdersDialog> createState() => _FakeOrdersDialogState();
}

class _FakeOrdersDialogState extends State<_FakeOrdersDialog> {
  late Future<List<Map<String, dynamic>>> _future = OpsService.tossFakeOrders(widget.storeId);
  final Set<String> _busy = {};

  // 81차: 가짜 포스에서 '결제 완료' 흉내 → 그 방 패드 주문이 다 끝나면 패드 언어가 로그인 때 언어로
  Future<void> _complete(Map<String, dynamic> o) async {
    final key = '${o['orderKey']}';
    setState(() => _busy.add(key));
    String msg;
    try {
      final r = await OpsService.tossFakeComplete(widget.storeId, o);
      msg = r['settled'] == true
          ? '${o['orderNumber'] ?? ''} 결제 끝 — 이 방 패드 언어가 로그인 때 언어로 돌아가요'
          : '결제 완료로 표시했어요${r['open'] is num ? ' (이 방에 아직 안 끝난 주문 ${r['open']}건)' : ''}';
    } catch (e) {
      msg = '$e';
    }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
    setState(() {
      _busy.remove(key);
      _future = OpsService.tossFakeOrders(widget.storeId);
    });
  }

  // 서버 시각(UTC, ISO) → 한국 시간 '2026-11-06 02:50:52'
  static String _kst(Object? iso) {
    final t = DateTime.tryParse('${iso ?? ''}');
    if (t == null) return '';
    final k = t.toUtc().add(const Duration(hours: 9));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${k.year}-${two(k.month)}-${two(k.day)} ${two(k.hour)}:${two(k.minute)}:${two(k.second)}';
  }

  String _lineText(Map li) {
    final title = (li['item'] is Map ? li['item']['title'] : null) ?? (li['itemPrice'] is Map ? li['itemPrice']['title'] : '') ?? '';
    final opts = [
      for (final c in (li['optionChoices'] as List? ?? const []))
        if ((c as Map)['title'] != null) '${c['title']}' else '옵션',
    ];
    final kind = li['targetType'] == 'ITEM' ? '' : ' (임의 상품)';
    return '$title${opts.isEmpty ? '' : ' [${opts.join(', ')}]'} x ${li['quantity']}$kind';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.storeId} — 가짜 포스에 들어온 주문'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) return Text('${snap.error}', style: const TextStyle(color: Colors.red));
            final list = snap.data ?? const [];
            if (list.isEmpty) return const Center(child: Text('아직 없어요. 손님 패드에서 주문해 보세요.'));
            return ListView(children: [
              for (final o in list)
                Card(
                  elevation: 0,
                  color: const Color(0xFFF6F7F9),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${o['orderNumber'] ?? ''}  ·  ${(o['chargePrice'] as Map?)?['totalAmount'] ?? ''}원  ·  ${_kst(o['createdAt'])}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      for (final li in (o['lineItems'] as List? ?? const [])) Text(_lineText(li as Map)),
                      if ((o['memo'] ?? '').toString().isNotEmpty)
                        Text('${o['memo']}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: o['posState'] == 'COMPLETED'
                            ? Text('결제 완료 ✓ ${_kst(o['completedAt'])}',
                                style: const TextStyle(color: Color(0xFF27AE60), fontSize: 12, fontWeight: FontWeight.w600))
                            : TextButton(
                                onPressed: _busy.contains('${o['orderKey']}') ? null : () => _complete(o),
                                child: const Text('결제 완료 (흉내)'),
                              ),
                      ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
    );
  }
}
