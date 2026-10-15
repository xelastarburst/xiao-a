# 小A (Little Alex)

An iPhone companion for Mom: live camera translation, Ask, a two-way interpreter, a daily
English coach, emergency help, and ride requests. Built from `PRD.md` (in the claude.ai Project).

## Run it

1. Open `XiaoA.xcodeproj` in Xcode (16 or later).
2. Select the **XiaoA** target › **Signing & Capabilities** › pick your Team.
   Change the bundle ID (`com.alexqi.xiaoa`) if Xcode says it's taken.
3. Plug in an iPhone (or pick a simulator) and press **Run**.

The camera, speech and interpreter features need a real iPhone. In the simulator, a Debug build
fills in sample details (names, 555 numbers, a sample insurance card) and plays short scripted
versions of Look, Ask, the interpreter and the coach's microphone, marked 模拟器示例 on screen.
None of it runs on a real iPhone.

## First-time setup on Mom's phone (Alex mode)

Long-press 小A on the home screen for 2 seconds.

- Your name and phone, Mom's name and phone, home address (English, optional Chinese)
- Places for rides (Chinese name + English address)
- Medical card and insurance card photos (stay on the phone, encrypted)
- API keys: OpenAI (interpreter) and Claude (Ask, coach tips) — saved in the Keychain
- **Download offline translation** on Wi-Fi so 看一看 works without data
- Set a PIN, and set the daily lesson reminder time
- Turn on Find My location sharing from her iPhone to yours. The Emergency screen tells her
  you can always see where she is, and this is what makes that true
- Run the emergency practice drill once with her

Also install the app on your own phone: Alex mode › **Send car details to Mom** turns Uber's
car info into a Chinese text for her.

## How each feature works

| Feature | How | Needs data |
|---|---|---|
| 看一看 Look | VisionKit live text + Apple Translation, on-device | No (after download) |
| 问一问 Ask | Photo + Mandarin voice (Apple speech) → `claude-sonnet-5-5` | Yes |
| 翻译官 Interpreter | Two `gpt-realtime-translate` sessions (→ English or German, → Chinese); Mom picks 对方说 英语 / 德语 | Yes |
| 学英语 Learn | Bundled 174-phrase curriculum; scoring by on-device English recognition; tips from `claude-haiku-5-5` | Tips only |
| 紧急 Emergency | 911 helper, call/text Alex with location, medical card | No (except text/location) |
| 叫车 Ride | Texts Alex her location, destination and a pre-filled Uber link | Yes |

## Known limits (v1)

- Rides and alerts go by text message; there's no in-app ride card or automatic alert yet.
- The interpreter's two-way routing relies on source transcripts; test it in a quiet room first.
- Freeze in 看一看 shows a captured photo behind the labels; label positions are approximate.
- Learn has 174 phrases in 29 units (about 6–7 weeks of new material at 4 a day), then review. Role-play isn't built yet.

## Install without a cable (TestFlight)

Needs the Apple Developer Program ($99/yr). Without it, apps installed from Xcode stop
opening after 7 days.
