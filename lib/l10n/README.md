# Guest pad languages

The guest pad supports Korean (`ko`), English (`en`), Simplified Chinese (`zh`),
and Japanese (`ja`). Use the globe menu in the header, including the room
selection screen. The choice is saved under `guest_language` in device
preferences and restored on startup. Language changes preserve navigation and
in-progress orders, timers, and group records.

`guest_messages.dart` contains interface translations. Korean filter identifiers,
menu option values, and win/loss values remain stable in storage and order payloads.
Flutter Material controls use the selected locale as well.

## Store content

Store-authored content is not automatically machine translated. Add optional
translated fields to Firestore records using this structure:

```json
{
  "title": "원문 게임 이름",
  "translations": {
    "en": { "title": "English game title", "players": "2–4 players", "time": "30 min", "genre": "Strategy", "tags": "Family" },
    "zh": { "title": "中文游戏名称" },
    "ja": { "title": "日本語のゲーム名" }
  }
}
```

Supported fields at display sites:

- Games: `title`, `players`, `time`, `genre`, `tags`.
- Menu cards and option dialogs: `name`; option groups: `groupName`; options: `name`.
- Notice and event items: `title`, `content` (including localized image URLs).

Missing or empty translations fall back to the original field. Images and videos
with embedded Korean text need separately translated assets. Player names, cafe
names, freeform bets and order requests are entered by customers and are kept as
entered. Cart records and order payloads preserve the original catalog names so
staff can identify ordered items consistently.

Validation: `flutter test` and `dart analyze lib test`.
