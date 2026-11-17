import 'package:flutter/material.dart';

/// 처리 중 버튼 잠그는 확인 창 (112차 — 100차 메뉴 삭제 규칙을 다른 확인 창에도)
///
/// 100차 규칙:
///  - 누르면 버튼을 바로 흐리게(글자는 그대로 — '…하는 중'으로 바꾸지 않음) + 다시 안 눌림
///  - 처리 중엔 [취소]·창 바깥 누르기·뒤로 가기도 막음
///  - 끝나면 창을 한 번만 닫음 (두 번 닫히면 아래 관리 화면까지 닫혀 하얀 화면이 됨)
///  - 실패하면 창을 그대로 두고 버튼을 다시 풀어 줌
///
/// [action]은 창 안에서 기다림. 성공하면 true, 취소하거나 실패하면 false.
/// 실패 문구는 창 아래 붉은 글자로 보여 줌 ([errorText]가 있으면 그 문구 + 오류).
Future<bool> showBusyConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function() action,
  String confirmLabel = '삭제',
  String cancelLabel = '취소',
  bool danger = true,
  String errorText = '처리하지 못했어요',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BusyConfirmDialog(
      title: title,
      message: message,
      action: action,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      danger: danger,
      errorText: errorText,
    ),
  );
  return ok == true;
}

/// 처리 중 흐려지는 꽉 찬 버튼 모양 (원래 색 반투명 — 100차)
ButtonStyle busyButtonStyle(Color color, {EdgeInsetsGeometry? padding}) => ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      disabledBackgroundColor: color.withValues(alpha: 0.45),
      disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
      padding: padding,
    );

class _BusyConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final Future<void> Function() action;
  final String confirmLabel;
  final String cancelLabel;
  final bool danger;
  final String errorText;

  const _BusyConfirmDialog({
    required this.title,
    required this.message,
    required this.action,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.danger,
    required this.errorText,
  });

  @override
  State<_BusyConfirmDialog> createState() => _BusyConfirmDialogState();
}

class _BusyConfirmDialogState extends State<_BusyConfirmDialog> {
  bool _busy = false;
  bool _closed = false; // 한 번만 닫기
  String? _error;

  void _close(bool result) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  Future<void> _run() async {
    if (_busy || _closed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.action();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${widget.errorText}: $e';
      });
      return;
    }
    _close(true);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.danger ? Colors.redAccent : const Color(0xFF1E2B3C);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.title,
            style: TextStyle(fontWeight: FontWeight.bold, color: widget.danger ? Colors.redAccent : null)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.message),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => _close(false),
            child: Text(widget.cancelLabel, style: TextStyle(color: _busy ? Colors.grey.shade300 : Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _busy ? null : _run,
            style: busyButtonStyle(color),
            child: Text(widget.confirmLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
