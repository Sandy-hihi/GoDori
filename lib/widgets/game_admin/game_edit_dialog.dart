import 'package:flutter/material.dart';

import 'package:boardpad/services/bgg_service.dart';
import 'game_form.dart';
import 'package:boardpad/services/store_scope.dart';

/// 등록된 게임 정보 수정 팝업. 저장하면 true를 돌려줌.
class GameEditDialog extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final List<String> genreList;
  const GameEditDialog({super.key, required this.docId, required this.data, required this.genreList});

  @override
  State<GameEditDialog> createState() => _GameEditDialogState();
}

class _GameEditDialogState extends State<GameEditDialog> {
  final GameForm _form = GameForm();
  bool _busy = false;
  String? _error;
  String? _note;

  @override
  void initState() {
    super.initState();
    _form.fillFromDoc(widget.data);
  }

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _lookup(String geekId) async {
    if (!RegExp(r'^\d+$').hasMatch(geekId)) {
      setState(() => _error = 'BGG geek ID는 숫자로 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _note = 'BGG에서 가져오는 중… (조금 걸릴 수 있어요)';
    });
    try {
      final warn = await fillFormFromBgg(_form, geekId, keepName: true, refresh: () {
        if (mounted) setState(() {});
      });
      if (!mounted) return;
      setState(() => _note = warn ?? 'BGG 정보로 채웠어요. 게임 이름은 그대로 두었어요. "저장"을 눌러야 반영돼요.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _note = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSearch() async {
    final picked = await showDialog<BggSearchResult>(
      context: context,
      builder: (_) => BggSearchDialog(initialQuery: _form.bggName ?? _form.name.text),
    );
    if (picked != null) await _lookup(picked.id);
  }

  Future<void> _save() async {
    Map<String, dynamic> fields;
    try {
      fields = _form.toFields(widget.genreList);
    } on GameFormError catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (imageFields, toDelete) = await _form.uploadImages();
      await StoreScope.col('games').doc(widget.docId).update({...fields, ...imageFields});
      for (final url in toDelete) {
        await deleteStorageUrl(url);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Game save error: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '저장에 실패했어요. 다시 시도해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('게임 정보 수정', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GeekIdRow(
                form: _form,
                busy: _busy,
                onLookup: () => _lookup(_form.geekId.text.trim()),
                onSearch: _openSearch,
              ),
              if (_note != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!, style: const TextStyle(color: Colors.black54, fontSize: 12))),
              const SizedBox(height: 16),
              GameFormFields(form: _form, genreList: widget.genreList),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: kAdminGreen, foregroundColor: Colors.white),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('저장', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
