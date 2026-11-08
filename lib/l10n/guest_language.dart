import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'guest_messages.dart';

/// Stable Korean values remain in filters, stored results and order payloads.
class GuestLanguage extends ChangeNotifier {
  GuestLanguage._();
  static final instance = GuestLanguage._();
  static const codes = ['ko', 'en', 'zh', 'ja'];
  static const names = ['한국어', 'English', '中文', '日本語'];

  /// Pretendard에 없는 한자·가나를 그릴 글꼴 (앱에 넣은 부분 글꼴, 81차).
  /// 일본어일 땐 일본식 한자 모양이 먼저 나오게 JP를 앞에.
  List<String> get fontFallback =>
      code == 'ja' ? const ['NotoSansJP', 'NotoSansSC'] : const ['NotoSansSC', 'NotoSansJP'];
  String code = 'ko';

  /// 로그인 때 고른 언어 (81차) — 토스 포스에서 그 방 결제가 끝나면 이 언어로 돌아감
  String defaultCode = 'ko';
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('guest_language');
      if (codes.contains(saved)) code = saved!;
      final def = prefs.getString('guest_language_default');
      defaultCode = codes.contains(def) ? def! : code;
    } catch (_) {
      /* Keep Korean when device storage is unavailable. */
    }
  }

  /// 패드 로그인 성공 때 부름 — 지금 언어를 기본 언어로 저장
  Future<void> rememberDefault() async {
    defaultCode = code;
    try {
      await (await SharedPreferences.getInstance()).setString('guest_language_default', code);
    } catch (_) {
      /* The default still works for the current session. */
    }
  }

  /// 손님이 바꾼 언어를 기본 언어로 되돌림 (방 결제 끝, 81차)
  Future<void> resetToDefault() => select(defaultCode);

  Future<void> select(String value) async {
    if (!codes.contains(value) || value == code) return;
    code = value;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(
        'guest_language',
        value,
      );
    } catch (_) {
      /* The selection still works for the current session. */
    }
  }

  /// 번역표에 똑같은 문장이 있을 때만 바꿈 (매장이 쓴 글 — 공지 제목·인사말 등, 81차).
  String translateExact(String text) {
    final i = codes.indexOf(code) - 1;
    if (i < 0) return text;
    return guestMessages[text.trim()]?[i] ?? text;
  }

  String translate(String text) {
    final i = codes.indexOf(code) - 1;
    if (i < 0) return text;
    final exact = guestMessages[text];
    if (exact != null) return exact[i];
    final dated = _translateDateTime(text, i);
    if (dated != null) return dated;
    if (text.startsWith('전체 ')) {
      return ['All ', '全部', 'すべての'][i] + translate(text.substring(3));
    }
    for (final rule in _patterns) {
      final match = rule.$1.firstMatch(text);
      if (match != null) {
        return rule.$2[i].replaceAllMapped(
          RegExp(r'\{(\d+)\}'),
          (m) => match.group(int.parse(m[1]!)) ?? '',
        );
      }
    }
    return text;
  }
}

// 시계: formatDateKo '11월 7일 (토)' · formatTimeKo '오후 10:01' (home_common.dart, 81차)
final _dateKo = RegExp(r'^(\d{1,2})월 (\d{1,2})일 \(([월화수목금토일])\)$');
final _timeKo = RegExp(r'^(오전|오후) (\d{1,2}):(\d{2})$');
const _weekKo = ['월', '화', '수', '목', '금', '토', '일'];
const _weekEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekZh = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const _weekJa = ['月', '火', '水', '木', '金', '土', '日'];
const _monthEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// i: 0 = en, 1 = zh, 2 = ja
String? _translateDateTime(String text, int i) {
  final d = _dateKo.firstMatch(text);
  if (d != null) {
    final m = int.parse(d[1]!), day = d[2]!, w = _weekKo.indexOf(d[3]!);
    if (m < 1 || m > 12 || w < 0) return null;
    return [
      '${_weekEn[w]}, ${_monthEn[m - 1]} $day',
      '$m月$day日（${_weekZh[w]}）',
      '$m月$day日（${_weekJa[w]}）',
    ][i];
  }
  final t = _timeKo.firstMatch(text);
  if (t != null) {
    final pm = t[1] == '오후', hm = '${t[2]}:${t[3]}';
    return [
      '$hm ${pm ? 'PM' : 'AM'}',
      '${pm ? '下午' : '上午'}$hm',
      '${pm ? '午後' : '午前'}$hm',
    ][i];
  }
  return null;
}

final _patterns = <(RegExp, List<String>)>[
  (RegExp(r'^(.*)번 룸$'), ['Room {1}', '{1}号房', '{1}号室']),
  (RegExp(r'^(.*)번 룸으로 가져다드려요$'), ['Delivered to Room {1}', '送至{1}号房', '{1}号室にお届けします']),
  (RegExp(r'^(.*) 담았어요$'), ['{1} added to cart', '{1} 已加入购物车', '{1} を追加しました']),
  (RegExp(r'^(.*)은\(는\) 지금 품절이에요\.$'), ['{1} is sold out.', '{1} 已售罄。', '{1} は品切れです。']),
  (RegExp(r'^(.*)원 담기$'), ['Add · ₩{1}', '加入 · ₩{1}', '追加 · ₩{1}']),
  (RegExp(r'^(\d+)개의 게임 · 가나다순$'), ['{1} games · Korean name order', '{1}款游戏 · 韩文名称排序', '{1}件のゲーム・韓国語名順']),
  (RegExp(r'^이 테이블에 맞는 게임 (\d+)개를 골랐어요$'), ['Found {1} games for your table', '为本桌挑选了{1}款游戏', 'このテーブルに合うゲームを{1}件選びました']),
  (RegExp(r'^(\d+)순위$'), ['Rank {1}', '第{1}名', '{1}位']),

  (RegExp(r'^(\d+)~(\d+)인$'), ['{1}–{2} players', '{1}至{2}人', '{1}～{2}人']),
  (RegExp(r'^(\d+)인$'), ['{1} players', '{1}人', '{1}人']),
  (RegExp(r'^(\d+)분$'), ['{1} min', '{1}分钟', '{1}分']),
  (RegExp(r'^(\d+)시간$'), ['{1} hr', '{1}小时', '{1}時間']),

  (RegExp(r'^(\d+)번 방$'), ['Room {1}', '{1}号房', '{1}号室']),
  (RegExp(r'^(\d+)인이상$'), ['{1}+ players', '{1}人以上', '{1}人以上']),
  (RegExp(r'^(\d+)명$'), ['{1} players', '{1}人', '{1}人']),
  (RegExp(r'^(\d+)번째 참가자$'), ['Player {1}', '参与者{1}', '参加者{1}']),
  (RegExp(r'^(\d+)번$'), ['Player {1}', '{1}号', '{1}番']),
  (RegExp(r'^(\d+)팀$'), ['Team {1}', '第{1}组', 'チーム{1}']),
  (RegExp(r'^(\d+)번째$'), ['Turn {1}', '第{1}位', '{1}番目']),
  (RegExp(r'^남은 인원: (\d+)명$'), ['Remaining: {1}', '剩余：{1}人', '残り：{1}人']),
  (RegExp(r'^랩 기록 \((\d+)\)$'), ['Laps ({1})', '分段记录（{1}）', 'ラップ記録（{1}）']),
  (
    RegExp(r'^(\d+)명에게 맞는 게임 · (\d+)개$'),
    ['Games for {1} players · {2}', '适合{1}人的游戏 · {2}款', '{1}人向けゲーム · {2}件'],
  ),
  (
    RegExp(r'^일행과 함께 · (\d+)번 방$'),
    ['Your group · Room {1}', '同行伙伴 · {1}号房', 'グループ · {1}号室'],
  ),
  (RegExp(r'^일행과 함께$'), ['Your group', '同行伙伴', 'グループ']),
  (
    RegExp(r'^승: (.*)\n패: (.*)\n(.*)$'),
    [
      'Winners: {1}\nLosers: {2}\n{3}',
      '赢家：{1}\n输家：{2}\n{3}',
      '勝者：{1}\n敗者：{2}\n{3}',
    ],
  ),
  (RegExp(r'^(.*) \(필수\)$'), ['{1} (required)', '{1}（必选）', '{1}（必須）']),
  (RegExp(r'^(.*) \(선택\)$'), ['{1} (optional)', '{1}（可选）', '{1}（任意）']),
  (
    RegExp(r'^판별 기록 · (\d+)판$'),
    ['Round history · {1}', '对局记录 · {1}局', '対戦記録 · {1}回'],
  ),
  (
    RegExp(r'^(\d+)판 · (.*)$'),
    ['Round {1} · {2}', '第{1}局 · {2}', '{1}回目 · {2}'],
  ),
  (
    RegExp(r'^(\d+)승 / (\d+)패$'),
    ['{1} wins / {2} losses', '{1}胜 / {2}负', '{1}勝 / {2}敗'],
  ),
  (
    RegExp(r'^현재 음료 내기 공동 당첨: (.*)$'),
    ['Drink bet — tied: {1}', '饮品打赌共同承担：{1}', 'ドリンク賭け・共同負担：{1}'],
  ),
  (
    RegExp(r'^현재 음료 내기 당첨: (.*)$'),
    ['Drink bet: {1}', '饮品打赌承担者：{1}', 'ドリンク賭け：{1}'],
  ),
  (RegExp(r'^(.*) 옵션 선택$'), ['{1} options', '{1} 选项', '{1} オプション']),
  (
    RegExp(r'^(.*) 담겼습니다\.$'),
    ['{1} added to cart.', '{1} 已加入购物车。', '{1} をカートに追加しました。'],
  ),
  (RegExp(r'^(\d+)원 담기$'), ['Add · ₩{1}', '加入 · ₩{1}', '追加 · ₩{1}']),
  (RegExp(r'^(.*?)([\d,]+)\s*원(.*)$'), ['{1}₩{2}{3}', '{1}₩{2}{3}', '{1}₩{2}{3}']),
];

String guestTr(BuildContext context, String text) {
  GuestLocaleScope.maybeWatch(context);
  return GuestLanguage.instance.translate(text);
}

/// Optional translated fields: translations.en.title, translations.zh.name, etc.
/// Original data is retained when the selected translation is missing.
String guestField(BuildContext context, Map data, String field) {
  GuestLocaleScope.maybeWatch(context);
  final translations = data['translations'];
  final localized = translations is Map
      ? translations[GuestLanguage.instance.code]
      : null;
  final value = localized is Map ? localized[field] : null;
  return value is String && value.trim().isNotEmpty
      ? value
      : (data[field] ?? '').toString();
}

class GuestLocaleScope extends InheritedNotifier<GuestLanguage> {
  GuestLocaleScope({super.key, required super.child})
    : super(notifier: GuestLanguage.instance);
  static void maybeWatch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<GuestLocaleScope>();
  }
}

/// Translation at presentation time keeps domain values and user input intact.
class GuestText extends StatelessWidget {
  const GuestText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: GuestLanguage.instance,
    builder: (context, _) => Text(
      GuestLanguage.instance.translate(data),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    ),
  );
}

// ── 언어 고르기 (82차 다시 만듦) ──
// 예전엔 Flutter 기본 팝업 메뉴(작은 분홍빛 목록)라 패드 디자인과 따로 놀았음
// → 사이드바 메뉴와 같은 모양의 줄 + 누르면 패드 색감의 큰 선택 창(버튼 4개)
// 색은 홈 화면(home_theme.dart)과 같은 값 — l10n이 화면 파일들을 불러오지 않게 여기 따로 둠
const _ink = Color(0xFF26211C);
const _bg = Color(0xFFF4F0E8);
const _orange = Color(0xFFE2711D);
const _muted = Color(0xFF7A7266);
const _line = Color(0xFFE6E1D7);
const _langSub = ['Korean', 'English', 'Chinese', 'Japanese'];

String get _currentName =>
    GuestLanguage.names[GuestLanguage.codes.indexOf(GuestLanguage.instance.code)];

/// 언어 선택 창 — 손님이 어느 언어를 쓰고 있든 알아보게 제목은 여러 언어로 고정
Future<void> showGuestLanguagePicker(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.45),
  builder: (_) => const _GuestLanguageDialog(),
);

class _GuestLanguageDialog extends StatelessWidget {
  const _GuestLanguageDialog();

  @override
  Widget build(BuildContext context) {
    final current = GuestLanguage.instance.code;
    return Dialog(
      backgroundColor: _bg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.translate_rounded, color: _orange),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '언어 / Language',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink),
                        ),
                        SizedBox(height: 2),
                        Text('语言 · 言語', style: TextStyle(fontSize: 14, color: _muted)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.4,
                  children: [
                    for (var i = 0; i < GuestLanguage.codes.length; i++)
                      _LanguageTile(
                        name: GuestLanguage.names[i],
                        sub: _langSub[i],
                        selected: GuestLanguage.codes[i] == current,
                        onTap: () {
                          GuestLanguage.instance.select(GuestLanguage.codes[i]);
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({required this.name, required this.sub, required this.selected, required this.onTap});
  final String name;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Material(
      color: selected ? _orange : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: selected ? BorderSide.none : const BorderSide(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: selected ? Colors.white : _ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(fontSize: 13, color: selected ? Colors.white.withValues(alpha: 0.85) : _muted),
                    ),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// 언어 버튼. 기본 = 작은 알약(패드 로그인 화면·사이드바를 끈 홈 오른쪽 위),
/// GuestLanguageButton.sidebar = 사이드바 메뉴 줄과 같은 모양(직원 호출 위)
class GuestLanguageButton extends StatelessWidget {
  const GuestLanguageButton({super.key}) : color = null, _sidebar = false;

  /// 사이드바용 — color: 사이드바 글자색
  const GuestLanguageButton.sidebar({super.key, required Color this.color}) : _sidebar = true;

  final Color? color;
  final bool _sidebar;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: GuestLanguage.instance,
    builder: (context, _) => _sidebar ? _buildSidebar(context) : _buildPill(context),
  );

  Widget _buildSidebar(BuildContext context) {
    final fg = color ?? _ink;
    return Material(
      color: fg.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showGuestLanguagePicker(context),
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.translate_rounded, size: 22, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _currentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: fg),
                  ),
                ),
                Icon(Icons.unfold_more_rounded, size: 20, color: fg.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPill(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: _line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showGuestLanguagePicker(context),
        child: SizedBox(
          height: 42,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.translate_rounded, size: 18, color: _ink),
                const SizedBox(width: 8),
                Text(_currentName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
                const SizedBox(width: 2),
                const Icon(Icons.expand_more_rounded, size: 18, color: _muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
