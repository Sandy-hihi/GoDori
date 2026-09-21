import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class AdminCallListener extends StatefulWidget {
  final Widget child;
  const AdminCallListener({super.key, required this.child});

  @override
  State<AdminCallListener> createState() => _AdminCallListenerState();
}

class _AdminCallListenerState extends State<AdminCallListener> {
  final _ringtonePlayer = FlutterRingtonePlayer();
  StreamSubscription<QuerySnapshot>? _subscription;
  bool _isInitialLoad = true;
  bool _isDialogShowing = false;
  final List<Map<String, dynamic>> _pendingCalls = [];
  StateSetter? _dialogSetState;

  @override
  void initState() {
    super.initState();
    _subscription = FirebaseFirestore.instance
        .collection('staff_calls')
        .where('isAcknowledged', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (_isInitialLoad) {
        _isInitialLoad = false;
        return;
      }
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          _ringtonePlayer.playNotification();
          final call = {
            'docId': change.doc.id,
            'roomNumber': data['roomNumber'],
          };
          if (_isDialogShowing && _dialogSetState != null) {
            // 다이얼로그가 이미 열려있으면 목록에 추가
            _dialogSetState!(() {
              _pendingCalls.add(call);
            });
          } else {
            _pendingCalls.add(call);
            if (mounted) _showCallsDialog();
          }
        }
      }
    });
  }

  void _showCallsDialog() {
    if (_isDialogShowing || !mounted) return;
    _isDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          _dialogSetState = setDialogState;
          return AlertDialog(
            title: const Text(
              '🔔 직원 호출',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
                fontSize: 22,
              ),
            ),
            content: SizedBox(
              width: 320,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _pendingCalls.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final call = _pendingCalls[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${call['roomNumber']}번 방에서 호출',
                          style: const TextStyle(fontSize: 17),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            await FirebaseFirestore.instance
                                .collection('staff_calls')
                                .doc(call['docId'] as String)
                                .update({'isAcknowledged': true});
                            setDialogState(() {
                              _pendingCalls.removeAt(index);
                            });
                            if (_pendingCalls.isEmpty && ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007E5B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 10),
                          ),
                          child: const Text(
                            '확인',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    ).then((_) {
      _isDialogShowing = false;
      _dialogSetState = null;
      _pendingCalls.clear();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
