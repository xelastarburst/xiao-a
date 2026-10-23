# 小A (Little Alex)

An iPhone companion for Mom: live camera translation, Ask, a two-way interpreter, a daily
English coach, emergency help, and ride requests. The full spec and decision log are in
[`docs/PRD.md`](docs/PRD.md).

## Repository

| Branch | App | Folder on Alex's Mac |
|---|---|---|
| `main` | **小A**, for Mom (Mandarin) | `~/Documents/xiao-a` |
| `german` | **Helferlein**, the German edition (no Learn) | `~/Documents/helferlein` |

Fixes that apply to both apps are made on `main` and merged into `german`.
`Parked/` holds two interpreter designs that were set aside (simultaneous translation and
voiceprint speaker detection); they are not part of the build.

## Run it

1. Open `XiaoA.xcodeproj` in Xcode (16 or later; iOS 18+).
2. Select the **XiaoA** target › **Signing & Capabilities** › pick your Team.
   Change the bundle ID (`com.alexqi.xiaoa`) if Xcode says it's taken.
3. Optional: add the API keys (below).
4. Plug in an iPhone (or pick a simulator) and press **Run**.

The camera, speech and interpreter features need a real iPhone. In the simulator, a Debug build
fills in sample details (names, 555 numbers, a sample insurance card) and plays short scripted
versions of Look, Ask, the interpreter and the coach's microphone, marked 模拟器示例 on screen.
None of it runs on a real iPhone.

## API keys

Keys are never in the code or in git. The app looks for them in this order:

1. The iPhone's Keychain, typed into Alex mode › API keys.
2. `XiaoA/BundledKeys.json`, built into the app so Mom's phone needs no typing. The file is
   git-ignored and exists only on Alex's Mac:

   ```json
   { "openai": "sk-…", "anthropic": "sk-ant-…" }
   ```

Without either, the app still builds and runs; the features that need the internet say so.

## First-time setup on Mom's phone (Alex mode)

Long-press 小A on the home screen for 2 seconds.

- Your name and phone, Mom's name and phone, home address (English, optional Chinese)
- Places for rides (Chinese name + English address)
- Medical card and insurance card photos (stay on the phone, encrypted)
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
| 看一看 Look | VisionKit live text + Apple Translation on-device; Claude refines steady or frozen text | No (after download) |
| 问一问 Ask | Photo + Mandarin voice (Apple speech) → `claude-sonnet-5-5` | Yes |
| 翻译官 Interpreter | Turn by turn: one OpenAI transcription stream → the language decides who spoke → `claude-sonnet-5-5` translates with context → OpenAI voice. Mom picks 对方说 英语 / 德语 | Yes |
| 学英语 Learn | Bundled 174-phrase curriculum; scoring by speech recognition; tips from `claude-haiku-5-5` | Tips only |
| 紧急 Emergency | 911 helper, call/text Alex with location, medical card | No (except text/location) |
| 叫车 Ride | Texts Alex her location, destination and a pre-filled Uber link | Yes |

## Tests

Product › Test on an iPhone simulator: 119 unit tests (Swift Testing) and 8 UI tests. They
never dial, text or call 911, and the UI tests run with no keys. Live checks against Claude and
OpenAI are off by default; to run them, tick `XIAOA_LIVE_API` under Product › Scheme ›
Edit Scheme › Test › Arguments (they use your keys and cost a little).

## Known limits (v1)

- Rides and alerts go by text message; there's no in-app ride card or automatic alert yet.
- The interpreter takes about 1.5–2.5 s per turn; test it in a quiet room first.
- Freeze in 看一看 shows a captured photo behind the labels; label positions are approximate.
- Learn has 174 phrases in 29 units (about 6–7 weeks of new material at 4 a day), then review. Role-play isn't built yet.

## Install without a cable (TestFlight)

Needs the Apple Developer Program ($99/yr). Without it, apps installed from Xcode stop
opening after 7 days.
