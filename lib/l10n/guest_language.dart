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

class GuestLanguageButton extends StatelessWidget {
  const GuestLanguageButton({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: GuestLanguage.instance,
    builder: (context, _) => PopupMenuButton<String>(
      tooltip: '언어 / Language / 语言 / 言語',
      initialValue: GuestLanguage.instance.code,
      onSelected: GuestLanguage.instance.select,
      itemBuilder: (_) => [
        for (var i = 0; i < GuestLanguage.codes.length; i++)
          CheckedPopupMenuItem(
            value: GuestLanguage.codes[i],
            checked: GuestLanguage.instance.code == GuestLanguage.codes[i],
            child: Text(GuestLanguage.names[i]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language),
            const SizedBox(width: 6),
            Text(
              GuestLanguage.names[GuestLanguage.codes.indexOf(
                GuestLanguage.instance.code,
              )],
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    ),
  );
}
