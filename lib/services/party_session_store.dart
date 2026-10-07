import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/party_session.dart';

abstract class PartySessionStore {
  Future<PartySession> load(int? roomNumber);
  Future<void> save(int? roomNumber, PartySession session);
}

/// Local to this device, separated by room. Does not create cafe orders.
class LocalPartySessionStore implements PartySessionStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  String _key(int? roomNumber) =>
      'party_session_v1_${roomNumber?.toString() ?? 'guest'}';

  @override
  Future<PartySession> load(int? roomNumber) async {
    final raw = await _preferences.getString(_key(roomNumber));
    if (raw == null) return PartySession();
    return PartySession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(int? roomNumber, PartySession session) =>
      _preferences.setString(_key(roomNumber), jsonEncode(session.toJson()));
}
