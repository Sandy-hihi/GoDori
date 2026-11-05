import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/party_session.dart';
import '../services/party_session_store.dart';
import 'game_list_screen.dart';
import 'food_order_screen.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/pad_shell.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/usage_meter.dart';

class PartyScreen extends StatefulWidget {
  final int? roomNumber;
  final PartySessionStore? store;
  final Future<List<Map<String, dynamic>>>? catalog;
  final Future<List<Map<String, dynamic>>>? menuCatalog;

  /// false면 왼쪽 사이드바 없이 (Firebase 없이 도는 위젯 테스트용)
  final bool showSidebar;
  const PartyScreen({
    super.key,
    this.roomNumber,
    this.store,
    this.catalog,
    this.menuCatalog,
    this.showSidebar = true,
  });

  @override
  State<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends State<PartyScreen> {
  final _names = TextEditingController();
  final _cafe = TextEditingController();
  final _drink = TextEditingController();
  final _count = TextEditingController(text: '4');
  final _game = TextEditingController();
  final _deck = BalanceDeck();
  late final PartySessionStore _store;
  late Future<List<Map<String, dynamic>>> _catalog;
  late BalanceQuestion _question;
  PartySession _session = PartySession();
  String? _menuId;
  bool _chooseMenu = false;
  Future<List<Map<String, dynamic>>>? _menus;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  int _playerCount = 4;
  String? _countError;
  String? _statsGame;
  final Map<String, String> _outcomes = {};
  final Map<String, bool> _votes = {};
  List<List<String>>? _teams;
  bool _randomTeams = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? LocalPartySessionStore();
    _catalog = _newCatalog();
    _question = _deck.next();
    _load();
  }

  Future<List<Map<String, dynamic>>> _newCatalog() {
    final future = _fetchCatalog();
    // Loading local records may finish later than the catalog request.
    // Retain errors for FutureBuilder without an unhandled early error.
    future.ignore();
    return future;
  }

  Future<List<Map<String, dynamic>>> _fetchCatalog() async {
    if (widget.catalog != null) return widget.catalog!;
    final snapshot = await StoreScope.col('games')
        .where('isAvailable', isEqualTo: true)
        .get()
        .metered();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final session = await _store.load(widget.roomNumber);
      if (!mounted) return;
      setState(() {
        _session = session;
        _syncInputs();
        if (session.players.isNotEmpty) {
          _playerCount = session.players.length;
          _count.text = _playerCount.toString();
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '기록을 불러오지 못했습니다. 다시 시도해주세요.';
        });
      }
    }
  }

  void _syncInputs() {
    _names.text = _session.players.join('\n');
    _cafe.text = _session.cafe;
    _drink.text = _session.drink;
    _menuId = _session.menuId;
    _chooseMenu = _menuId != null;
    if (_chooseMenu) _loadMenus();
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _save(PartySession next) async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      await _store.save(widget.roomNumber, next);
      if (!mounted) return false;
      setState(() => _session = next);
      return true;
    } catch (_) {
      if (mounted) _message('저장하지 못했습니다. 기존 기록은 유지됩니다. 다시 시도해주세요.');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSetup() async {
    final players = _names.text
        .split(RegExp(r'[,\n]'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (players.length < 2 || players.length > 30) {
      _message('참가자를 2~30명 입력하세요.');
      return;
    }
    if (players.any((p) => p.length > 30) ||
        players.toSet().length != players.length) {
      _message('이름은 30자 이내로, 동명이인은 서로 다른 별명으로 입력하세요.');
      return;
    }
    if (_chooseMenu && _menuId == null) {
      _message('주문 메뉴를 선택하거나 직접 입력으로 전환하세요.');
      return;
    }
    final next = PartySession(
      players: players,
      cafe: _cafe.text.trim(),
      drink: _drink.text.trim(),
      menuId: _chooseMenu ? _menuId : null,
    );
    if (await _save(next) && mounted) {
      setState(() {
        _syncInputs();
        _votes.clear();
        _outcomes.clear();
        _teams = null;
        _statsGame = null;
        _playerCount = players.length;
        _count.text = players.length.toString();
        _countError = null;
      });
      _message('일행 설정을 저장했습니다.');
    }
  }

  Future<void> _recordRound() async {
    if (_session.players.length < 2 ||
        _session.cafe.isEmpty ||
        _session.drink.isEmpty) {
      _message('승패를 기록하기 전에 일행, 카페와 음료·내기 내용을 저장하세요.');
      return;
    }
    final winners = _session.players.where((p) => _outcomes[p] == '승').toList();
    final losers = _session.players.where((p) => _outcomes[p] == '패').toList();
    if (_game.text.trim().isEmpty || winners.isEmpty || losers.isEmpty) {
      _message('게임 이름과 승자·패자를 각각 한 명 이상 선택하세요.');
      return;
    }
    final round = GameRound(
      game: _game.text.trim(),
      playedAt: DateTime.now(),
      winners: winners,
      losers: losers,
    );
    if (await _save(_session.withRounds([..._session.rounds, round])) &&
        mounted) {
      setState(() {
        _outcomes.clear();
        _statsGame = null;
      });
      _message('승패 기록을 저장했습니다.');
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _removeRound(int index) async {
    if (!await _confirm('기록 삭제', '이 판의 승패 기록을 삭제하고 집계를 다시 계산할까요?')) return;
    final rounds = [..._session.rounds]..removeAt(index);
    if (await _save(_session.withRounds(rounds)) && mounted) {
      setState(() => _statsGame = null);
    }
  }

  Future<void> _reset() async {
    if (!await _confirm(
      '새 일행 시작',
      '현재 방의 참가자와 모든 승패·내기 기록이 삭제됩니다. 새로 시작할까요?',
    )) {
      return;
    }
    if (await _save(PartySession()) && mounted) {
      setState(() {
        _syncInputs();
        _outcomes.clear();
        _votes.clear();
        _teams = null;
        _statsGame = null;
        _game.clear();
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [_names, _cafe, _drink, _count, _game]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: PadShell(
        current: 'party',
        roomNumber: widget.roomNumber,
        showSidebar: widget.showSidebar,
        title: '일행과 함께',
        subtitle: '인원별 추천 · 승패 기록과 음료 내기 · 밸런스 게임으로 팀 나누기',
        headerBottom: const PadTabBar(
          tabs: [
            Tab(text: '인원별 추천'),
            Tab(text: '승패 · 음료 내기'),
            Tab(text: '밸런스 게임 · 팀'),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!),
                    TextButton(onPressed: _load, child: const Text('다시 시도')),
                  ],
                ),
              )
            : AbsorbPointer(
                absorbing: _saving,
                child: Column(
                  children: [
                    if (_saving) const LinearProgressIndicator(color: kOrange),
                    Expanded(
                      child: TabBarView(
                        children: [_recommendations(), _records(), _balance()],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _page(List<Widget> children) =>
      ListView(padding: const EdgeInsets.fromLTRB(32, 0, 32, 24), children: children);

  Widget _card(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _recommendations() => _page([
    _card('몇 명이 함께 하나요?', [
      TextField(
        controller: _count,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: '인원 수',
          suffixText: '명',
          errorText: _countError,
        ),
        onSubmitted: (_) => _recommend(),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _recommend,
        icon: const Icon(Icons.search),
        label: const Text('인원에 맞는 게임 추천'),
      ),
      const SizedBox(height: 8),
      const Text('카페에 등록된 이용 가능 게임 중 최소·최대 인원이 맞는 게임입니다. 직원 추천 게임을 먼저 표시합니다.'),
    ]),
    FutureBuilder<List<Map<String, dynamic>>>(
      future: _catalog,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _catalogError();
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final games = snapshot.data!
            .where(
              (g) => supportsPlayerCount(
                (g['players'] ?? '').toString(),
                _playerCount,
              ),
            )
            .toList();
        games.sort((a, b) {
          final priority =
              (b['isRecommended'] == true ? 1 : 0) -
              (a['isRecommended'] == true ? 1 : 0);
          return priority != 0
              ? priority
              : (a['title'] ?? '').toString().compareTo(
                  (b['title'] ?? '').toString(),
                );
        });
        return _card('$_playerCount명에게 맞는 게임 · ${games.length}개', [
          if (games.isEmpty)
            const Text('해당 인원에 맞는 등록 게임이 없습니다. 다른 인원을 입력하거나 직원에게 문의해주세요.'),
          for (final game in games)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                game['isRecommended'] == true ? Icons.star : Icons.extension,
                color: kOrange,
              ),
              title: Text((game['title'] ?? '이름 없는 게임').toString()),
              subtitle: Text(
                [game['players'], game['time'], game['difficulty']]
                    .where((v) => v != null && v.toString().isNotEmpty)
                    .join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GameListScreen(
                    initialSearchQuery: (game['title'] ?? '').toString(),
                    roomNumber: widget.roomNumber,
                  ),
                ),
              ),
            ),
        ]);
      },
    ),
  ]);

  void _recommend() {
    final count = int.tryParse(_count.text);
    setState(() {
      if (count == null || count < 1 || count > 100) {
        _countError = '1~100명 사이의 인원을 입력하세요.';
      } else {
        _countError = null;
        _playerCount = count;
      }
    });
  }

  Widget _catalogError() => _card('게임 목록을 불러오지 못했습니다', [
    const Text('연결을 확인하고 다시 시도해주세요.'),
    TextButton(
      onPressed: () => setState(() => _catalog = _newCatalog()),
      child: const Text('목록 다시 불러오기'),
    ),
  ]);

  void _loadMenus() {
    _menus ??=
        widget.menuCatalog ??
        StoreScope.col('menus')
            .get()
            .then(
              (snapshot) => snapshot.docs
                  .where(
                    (doc) =>
                        doc.data()['isSoldOut'] != true &&
                        doc.data()['isSoldOut'] != 'true',
                  )
                  .map((doc) => {...doc.data(), 'id': doc.id})
                  .toList(),
            );
    _menus!.ignore();
  }

  Widget _betInput(bool locked) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('직접 입력'),
            selected: !_chooseMenu,
            onSelected: locked
                ? null
                : (_) => setState(() {
                    _chooseMenu = false;
                    _menuId = null;
                  }),
          ),
          ChoiceChip(
            label: const Text('주문 메뉴에서 선택'),
            selected: _chooseMenu,
            onSelected: locked
                ? null
                : (_) => setState(() {
                    _chooseMenu = true;
                    _loadMenus();
                  }),
          ),
        ],
      ),
      if (_chooseMenu)
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _menus,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  const Text('주문 메뉴를 불러오지 못했습니다. 직접 입력하거나 다시 시도하세요.'),
                  TextButton(
                    onPressed: () => setState(() {
                      _menus = null;
                      _loadMenus();
                    }),
                    child: const Text('메뉴 다시 불러오기'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final menus = snapshot.data!;
            final available = menus.any((m) => m['id'] == _menuId);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (menus.isEmpty) const Text('주문 가능한 메뉴가 없습니다. 직접 입력해주세요.'),
                if (_menuId != null && !available)
                  const Text('선택했던 메뉴가 삭제되었거나 품절되었습니다.'),
                DropdownButtonFormField<String>(
                  key: ValueKey('bet_menu_${_menuId ?? ''}_$available'),
                  initialValue: available ? _menuId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '음식 · 음료 주문 메뉴'),
                  items: menus
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m['id'] as String,
                          child: Text(
                            "${m['name']} · ${m['price']}원",
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: locked
                      ? null
                      : (id) => setState(() {
                          _menuId = id;
                          _drink.text = menus
                              .firstWhere((m) => m['id'] == id)['name']
                              .toString();
                        }),
                ),
              ],
            );
          },
        ),
      TextField(
        controller: _drink,
        enabled: !locked,
        maxLength: 120,
        decoration: InputDecoration(
          labelText: _chooseMenu ? '선택 메뉴 · 내기 내용' : '음료 · 내기 내용',
          hintText: '예: 모두의 아메리카노 한 잔씩 사기',
        ),
      ),
    ],
  );

  Widget _setup() {
    final locked = _session.rounds.isNotEmpty;
    return _card('일행과 음료 내기 설정', [
      const Text(
        '이름은 줄바꿈 또는 쉼표로 구분하세요. 동명이인은 별명으로 구분하세요. 밸런스 팀 나누기는 이름만 저장해도 됩니다. 승패 기록 전에는 카페와 음료 내기를 정해주세요.',
      ),
      TextField(
        controller: _names,
        minLines: 2,
        maxLines: 5,
        enabled: !locked,
        decoration: const InputDecoration(
          labelText: '참가자 이름',
          hintText: '민수, 지수, 도리',
        ),
      ),
      TextField(
        controller: _cafe,
        enabled: !locked,
        maxLength: 80,
        decoration: const InputDecoration(
          labelText: '미리 정한 보드게임 카페',
        ),
      ),
      _betInput(locked),
      if (_session.menuId != null)
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FoodOrderScreen(
                roomNumber: widget.roomNumber,
                initialMenuId: _session.menuId,
              ),
            ),
          ),
          icon: const Icon(Icons.shopping_cart_outlined),
          label: const Text('선택 메뉴 주문하기'),
        ),
      if (!locked)
        FilledButton(onPressed: _saveSetup, child: const Text('일행과 내기 저장')),
      if (locked) const Text('첫 기록 이후에는 참가자와 내기 조건이 고정됩니다. 변경하려면 새 일행을 시작하세요.'),
      const SizedBox(height: 8),
      const Text('이 기기에 방별로 저장됩니다. 다른 기기와 공유되지 않으며 실제 음료 주문은 전송하지 않습니다.'),
      TextButton(onPressed: _reset, child: const Text('새 일행 시작 · 기록 초기화')),
    ]);
  }

  Widget _records() => _page([
    _setup(),
    if (_session.players.isNotEmpty) ...[
      _card('게임 한 판 기록', [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _catalog,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('등록 게임을 불러오지 못했습니다. 아래에 게임 이름을 직접 입력할 수 있습니다.');
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final titles =
                snapshot.data!
                    .map((g) => (g['title'] ?? '').toString())
                    .where((t) => t.isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort();
            if (titles.isEmpty) return const Text('등록 게임이 없습니다. 이름을 직접 입력하세요.');
            return DropdownButtonFormField<String>(
              key: ValueKey(_game.text),
              initialValue: titles.contains(_game.text) ? _game.text : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '등록 게임 선택'),
              items: titles
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (value) => setState(() => _game.text = value ?? ''),
            );
          },
        ),
        TextField(
          controller: _game,
          maxLength: 100,
          decoration: const InputDecoration(labelText: '게임 이름 · 직접 입력 가능'),
        ),
        const Text('승자·패자를 선택하세요. 함께 하지 않은 사람은 미참가로 두세요.'),
        for (final player in _session.players)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  player,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final outcome in ['미참가', '승', '패'])
                  ChoiceChip(
                    key: ValueKey('outcome_${player}_$outcome'),
                    label: Text(outcome),
                    selected: (_outcomes[player] ?? '미참가') == outcome,
                    onSelected: (_) =>
                        setState(() => _outcomes[player] = outcome),
                  ),
              ],
            ),
          ),
        FilledButton.icon(
          onPressed: _recordRound,
          icon: const Icon(Icons.save),
          label: const Text('이 판의 승패 저장'),
        ),
      ]),
      _scoreboard(),
      _card('판별 기록 · ${_session.rounds.length}판', [
        if (_session.rounds.isEmpty) const Text('아직 기록이 없습니다.'),
        for (var i = _session.rounds.length - 1; i >= 0; i--)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${i + 1}판 · ${_session.rounds[i].game}'),
            subtitle: Text(
              '승: ${_session.rounds[i].winners.join(', ')}\n패: ${_session.rounds[i].losers.join(', ')}\n${_session.rounds[i].playedAt.toLocal().toString().split('.').first}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: '이 판 기록 삭제',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removeRound(i),
            ),
          ),
      ]),
    ],
  ]);

  Widget _scoreboard() {
    final games = _session.rounds.map((r) => r.game).toSet().toList()..sort();
    final wins = _session.wins(game: _statsGame);
    final losses = _session.losses(game: _statsGame);
    final players = [..._session.players]
      ..sort((a, b) => losses[b]!.compareTo(losses[a]!));
    final drinkWinners = _session.drinkWinners;
    return _card('승패 집계와 음료 내기', [
      DropdownButtonFormField<String>(
        key: ValueKey(_statsGame),
        initialValue: _statsGame ?? '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: '게임별 기록 보기'),
        items: [
          const DropdownMenuItem(value: '', child: Text('전체 게임')),
          ...games.map((g) => DropdownMenuItem(value: g, child: Text(g))),
        ],
        onChanged: (value) =>
            setState(() => _statsGame = value == '' ? null : value),
      ),
      for (final player in players)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(player),
          trailing: Text('${wins[player]}승 / ${losses[player]}패'),
        ),
      const Divider(),
      Text(
        drinkWinners.isEmpty
            ? '기록이 쌓이면 음료 내기 당첨자가 표시됩니다.'
            : '현재 음료 내기 ${drinkWinners.length > 1 ? '공동 당첨: ' : '당첨: '}${drinkWinners.join(', ')}',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: kOrange,
        ),
      ),
      Text('${_session.cafe} · ${_session.drink}'),
      const Text(
        '내기는 전체 게임의 누적 패배 횟수로 계산합니다. 가장 많이 패한 사람이 당첨되며 동률이면 공동 당첨입니다.',
      ),
    ]);
  }

  Widget _balance() => _page([
    _card('대화의 시작, 밸런스 게임', [
      const Text('정답은 없어요. 각자 고른 이유를 이야기해보세요!'),
      const SizedBox(height: 16),
      Text(
        'A · ${_question.a}',
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('VS'),
      ),
      Text(
        'B · ${_question.b}',
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => setState(() {
          _question = _deck.next();
          _votes.clear();
          _teams = null;
        }),
        icon: const Icon(Icons.shuffle),
        label: const Text('다음 랜덤 질문'),
      ),
      const Text('준비된 30개 질문을 무작위로 뽑습니다. 한 바퀴가 돌기 전에는 같은 질문이 반복되지 않습니다.'),
    ]),
    if (_session.players.isEmpty)
      _card('선택으로 팀 나누기', [
        const Text('승패 · 음료 내기 탭에서 일행 이름을 저장하면 선택으로 팀을 나눌 수 있습니다.'),
        Builder(
          builder: (context) => TextButton(
            onPressed: () => DefaultTabController.of(context).animateTo(1),
            child: const Text('일행 이름 입력하기'),
          ),
        ),
      ])
    else
      _card('일행의 선택', [
        for (final player in _session.players)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  player,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                ChoiceChip(
                  label: const Text('A'),
                  selected: _votes[player] == true,
                  onSelected: (_) => setState(() {
                    _votes[player] = true;
                    _teams = null;
                  }),
                ),
                ChoiceChip(
                  label: const Text('B'),
                  selected: _votes[player] == false,
                  onSelected: (_) => setState(() {
                    _votes[player] = false;
                    _teams = null;
                  }),
                ),
              ],
            ),
          ),
        Text('선택 완료: ${_votes.length} / ${_session.players.length}명'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _votes.length != _session.players.length
              ? null
              : () => setState(() {
                  _teams = choiceTeams(_session.players, _votes);
                  _randomTeams = false;
                }),
          child: const Text('A/B 선택으로 팀 나누기'),
        ),
        OutlinedButton(
          onPressed: _votes.length != _session.players.length
              ? null
              : () => setState(() {
                  _teams = balancedRandomTeams(_session.players, Random());
                  _randomTeams = true;
                }),
          child: const Text('선택과 별개로 인원 균등 랜덤 팀'),
        ),
        if (_teams != null) ...[
          const Divider(),
          Text(
            _randomTeams ? '인원 균등 랜덤 팀 결과' : '같은 선택을 한 사람끼리 팀',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          for (var i = 0; i < 2; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${_randomTeams
                    ? (i + 1).toString()
                    : i == 0
                    ? 'A'
                    : 'B'}팀 · ${_teams![i].length}명',
              ),
              subtitle: Text(
                _teams![i].isEmpty ? '선택한 사람이 없습니다.' : _teams![i].join(', '),
              ),
            ),
          if (!_randomTeams && _teams!.any((t) => t.isEmpty))
            const Text('모두 같은 답을 골랐네요! 다음 질문으로 다시 고르거나 인원 균등 랜덤 팀을 이용하세요.'),
        ],
      ]),
  ]);
}
