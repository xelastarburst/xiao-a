# PRD — "小A" (Little Alex): an iPhone companion for Mom

| | |
|---|---|
| Owner | Alex |
| Status | v1 built and every screen tested in the simulator; on Alex's iPhone for real-device testing (2026-10-14) |
| Last updated | 2026-10-14 |
| Working name | 小A ("Little Alex") — placeholder, see Open Questions |

---

## 1. Overview

Mom speaks Mandarin, reads Simplified Chinese, and is a total beginner in English. She is spending two to three months in the US and is often on her own while Alex is at work. Today almost every unfamiliar sign, menu, label, conversation or errand turns into a call to Alex.

**小A is a "mini Alex" in her pocket.** It reads English for her, interprets conversations, teaches her survival English for 30 minutes a day, gets her help in an emergency, and books rides with Alex's approval. Everything is in Chinese, voice-first, friendly and cute, and fast enough to use while she is standing at a counter.

### Goals
1. Mom can understand any English text she sees and hold a basic conversation with English speakers, without calling Alex.
2. Mom builds real, spoken survival English through a daily 30-minute habit.
3. Mom can get help in an emergency in two taps or fewer, even with no data connection.
4. Mom can get a ride somewhere without knowing how to use Uber.

### Non-goals (v1)
- Languages other than Mandarin ↔ English. Exception: the interpreter also does Mandarin ↔ German (added 2026-10-14).
- Maps and turn-by-turn navigation. Apple or Google Maps already does this.
- Accounts, social features, or use by anyone other than Mom and Alex.
- App Store release. v1 is distributed privately through TestFlight.
- Waymo booking. See F4.

### Success metrics (measured over the visit)
- Mom uses 小A on her own on at least 5 days a week.
- She completes the daily lesson on at least 5 of 7 days.
- "What does this say?" calls to Alex drop noticeably within the first two weeks.
- Every emergency action passes a monthly test run.
- By the end of the visit she can say ~100 core phrases (about 2 per lesson) clearly enough to pass the coach's check.

---

## 2. Users

**Mom (primary).** 67. Mandarin speaker who reads Simplified Chinese. Total beginner in English and doesn't read the English alphabet yet. Comfortable with a smartphone at the level of WeChat-style apps: tapping, voice messages, the camera. She needs big text, clear sounds, and no dead ends.

**Alex (caregiver/admin).** Sets the app up, keeps her contacts, places and emergency info up to date, approves rides, and checks her lesson progress. Usually busy, so anything that needs Alex should be one tap.

---

## 3. Design principles

1. **Chinese-first.** Every label, prompt, error and answer is in Simplified Chinese. English appears only as content, such as the thing being translated or the phrase being learned.
2. **Voice-first.** She can speak instead of typing anywhere input is needed, and any text in the app can be read aloud with one tap.
3. **Friendly and cute.** A small mascot (a "mini Alex" character) guides, cheers and comforts her. The look is soft and rounded, with warm colors and gentle animations and sounds. Nothing feels clinical.
4. **Big and simple.** At most 6 tiles on the home screen. Tap targets are at least 60pt and body text at least 20pt, with Dynamic Type supported. There is one primary action per screen and the 返回 (back) button is always in the same place.
5. **Instant feedback.** Every tap responds within 100 ms with an animation, haptic or sound, even when the real work takes longer.
6. **Never stranded.** Every failure says what happened in plain Chinese and offers a next step: try again, use offline mode, or call Alex.
7. **Emergency is always one tap away.** A red 紧急 button is visible on every screen. One exception: the interpreter while a conversation is running (see F1c).

### Home screen (draft)

| Tile | Chinese label | Feature |
|---|---|---|
| 1 | 看一看 (Look) | F1a — live camera translation |
| 2 | 问一问 (Ask) | F1b — ask about what she sees |
| 3 | 翻译官 (Interpreter) | F1c — live two-way interpreter |
| 4 | 学英语 (Learn English) | F2 — daily coach |
| 5 | 叫车 (Get a ride) | F4 — ride agent |
| Always visible | 紧急 (Emergency) | F3 — emergency |

---

## 4. Features

Priority follows Alex's ranking: **P0 = F1, P1 = F2, P2 = F3, P3 = F4.** The build order in §8 pulls F3 earlier because it is small and safety-critical. The priority itself is unchanged.

### F1 — Overcome the language barrier (P0)

#### F1a. Live camera translation overlay
**Story:** When Mom points her camera at English (a sign, menu, mail, medicine label or product), she sees Chinese drawn on top of the English, in place, in real time.

Requirements
- Live camera view. Each detected English text block is overlaid with its Simplified Chinese translation, positioned and sized to match the original.
- Translation updates continuously as the camera moves, with no shutter button needed.
- **Freeze** button to pause the frame so she can read calmly. A frozen frame can be sent to F1b with one tap.
- **Read aloud** button for any translated block, in Chinese.
- Toggle to show the original English, for learning.
- Flashlight toggle for dim restaurants.
- Must work **offline**, using on-device recognition and translation.

Acceptance
- Chinese overlay appears within **1 second** of text entering the frame.
- The overlay follows the camera without visible lag.
- It works on printed text in normal indoor light. Handwriting is best-effort.
- Benchmark: it must feel at least as fast as the camera mode in Apple's Translate app.

Candidate tech (final choice in build): on-device Apple Vision text recognition plus the Apple Translation framework (English → Simplified Chinese, offline language pack). Cloud models are too slow for per-frame overlay. They are used only in F1b.

**As built (2026-10-14):** the overlay appears instantly from on-device recognition and Apple Translation. When the camera rests on something for ~0.7 s, Claude Haiku re-translates everything in view together so each line fits what the thing is (menu, label, sign). **放大** zooms 2× for small print. **定住画面** reads the full-resolution photo with Apple Vision's most careful mode (including fine print) and has Claude Sonnet translate it with the photo in view, paragraph by paragraph.

#### F1b. Ask about what she's seeing
**Story:** After freezing a frame or taking a photo, Mom asks a question in Chinese, such as "这个药一天吃几次?" ("How many times a day do I take this?") or "这个是什么意思?" ("What does this mean?"), and gets a clear Chinese text answer.

Requirements
- She can ask by holding a mic button and speaking Mandarin, or by typing.
- The answer is in Simplified Chinese **text**, short and plain-spoken, with an optional read-aloud button.
- She can ask follow-up questions in the same thread, with the image kept in context.
- **Safety framing for medicine, money and legal or official mail:** the answer explains what the text says and suggests checking with Alex or a pharmacist/doctor before acting. It never invents a dosage that isn't printed.
- An **"Ask Alex"** button forwards the photo, her question and the AI's answer to Alex.
- Alex can preload personal context, such as home address, his name and her usual stores, so answers feel personal.

Acceptance
- The answer starts streaming within **2 seconds** of her finishing the question.
- If there's no connection, she sees a clear message and the F1a overlay is still available.

Candidate tech: Claude Sonnet 5.5 (vision, strong Chinese) for answers, with Claude Haiku 5.5 or a GPT equivalent as a lower-latency option. Speech-to-text by gpt-realtime-whisper or Apple on-device speech recognition. To be benchmarked on real photos in the build phase.

#### F1c. Live interpreter
**Story:** Mom taps 翻译官, picks the other person's language, and presses the big 开始对话 button. The phone becomes an interpreter. She speaks Mandarin and the phone speaks English aloud. Her friend replies in English and the phone speaks Mandarin to her. It stays on until she presses 结束对话, and then what was said stays on screen so she can read it again. **German too:** a 对方说 英语 | 德语 switch makes it Chinese ↔ German for German-speaking friends; the choice is remembered.

Requirements
- **Mom starts it and Mom ends it.** Nothing listens until she presses the big round 开始对话 button on the start screen (where she also picks 英语 or 德语). During the conversation the only exit is one big 结束对话 button; there is no 紧急 button next to it, so nothing can be pressed by mistake. After she ends it, a 说完了 screen keeps the conversation with 再开始 and 回首页. 紧急 is in the top bar of the start and end screens.
- **Always on once started.** Hands-free, with no push-to-talk. It detects who is speaking by language and translates in the right direction automatically.
- **Two-sided screen.** The bottom half shows Mom's view (Chinese captions, large). The top half is rotated 180° so a person across the table can read English captions.
- A running transcript of both languages, with each line replayable.
- Built-in phrases: "请说慢一点" ("Please speak slower") plays as English. "我不会说英语" ("I don't speak English") plays as an icebreaker at start.
- Must not translate its own speech output (echo/feedback protection).
- Clear "listening / translating / speaking" state, using the mascot animation.
- Gentle prompt after 10 minutes of silence asking whether to keep listening, to protect battery and data. It never stops without asking.
- Works with the iPhone speaker by default, with optional AirPods.

Acceptance
- Translated speech starts within **~1.5–2 seconds** of the speaker pausing.
- Correct direction is chosen at least 95% of the time in a quiet room.
- It runs for 30 minutes without dropping.

**As built (2026-10-14, turn by turn):** one OpenAI realtime transcription stream (gpt-4o-transcribe, falling back to gpt-4o-mini-transcribe) hears everyone and ends a sentence after 0.7 s of quiet. Chinese in the transcript means Mom spoke; anything else is the other person. Claude Sonnet translates each sentence with the last 8 lines as context. OpenAI gpt-4o-mini-tts says it, one turn at a time, with the phone's own voice as backup. The earlier simultaneous design (below) is parked in `Parked/simultaneous-interpreter/`.

Original candidate tech: **OpenAI gpt-realtime-translate**, released May 2026. It is a streaming speech-to-speech translation model whose output languages include both Chinese and English, priced at about $0.034 per audio minute. Two-way routing (one session per direction vs. switching by detected language) is a build-phase decision. Fallback if it falls short: gpt-realtime-2 with an interpreter prompt, or Apple's on-device translation as an offline backup.

### F2 — Daily learning coach (P1)

**Story:** Every day Mom does a 30-minute spoken lesson. A friendly coach explains in Chinese, she says the English phrase first, and the coach corrects her pronunciation until she gets it, then moves on.

Lesson loop (per phrase)
1. The coach introduces the situation and meaning in Chinese, e.g. "在超市,你想问厕所在哪里。" ("At the supermarket, you want to ask where the restroom is.")
2. **She speaks first.** She tries the phrase after one model playback.
3. The coach scores the attempt and gives one specific fix in Chinese, e.g. "'restroom' 的 'r' 要卷一下舌头。" ("Curl your tongue a little for the 'r' in 'restroom'.") It replays the target, slowed if needed.
4. She repeats until the attempt **passes the threshold**, then the coach celebrates and moves on.
5. Phrases that took many tries go into tomorrow's review.

> **On "perfect":** for a total beginner at 67, demanding perfection on every phrase risks frustration and quitting. Default: the pass bar is "clearly understandable to a native speaker." After 4 tries the coach praises her effort, marks the phrase for review, and moves on. Alex can raise the bar in settings.

Daily structure (30 min)
| Segment | Time | What happens |
|---|---|---|
| Warm-up review | 5 min | Phrases from previous days, with weakest first |
| New phrases | 15 min | 3–5 new phrases from today's unit |
| Role-play | 8 min | The coach plays a cashier, driver or neighbor; she uses today's phrases |
| Wrap-up | 2 min | Stars, streak, mascot celebration, preview of tomorrow |

Curriculum (total beginner, ordered by survival value; ~60 lessons ≈ 2–3 months)
1. Greetings and politeness (hello, thank you, sorry, excuse me)
2. Survival basics (yes/no, I don't understand, please speak slowly, help)
3. Numbers, prices and money
4. Grocery and shopping
5. Ordering food and coffee
6. Rides, transport and directions
7. Her own info (name, Alex's name, home address, phone number)
8. Pharmacy and doctor
9. Emergencies (what to say to 911 and to strangers)
10. Neighbors and small talk
11. Time, days and appointments

Requirements
- English is shown with Chinese meaning and a simple pronunciation hint. Teaching the alphabet is not a prerequisite.
- A daily reminder at a time Alex sets, voiced by the mascot.
- Streaks, stars and stickers, with gentle and never-guilty messaging if she misses a day.
- A pause and resume button, in case she gets interrupted.
- Alex sees progress: days completed, phrases mastered, and phrases she struggles with.
- **(Nice-to-have)** Phrases she used or looked up in F1 can be added to her review deck.

Acceptance
- Coach feedback begins within **1.5 seconds** of her finishing an attempt.
- Lesson content is available offline. Scoring needs a connection.

Candidate tech: **OpenAI gpt-realtime-2** (May 2026, speech-to-speech) as the live coach voice. Curriculum content is authored once with Claude Opus 5.5, reviewed by Alex, and bundled in the app, which keeps it consistent, cheap and offline. **Risk:** general LLM audio judgment is approximate at the sound level. If it can't reliably catch her mistakes, add a dedicated pronunciation-assessment service that scores individual sounds. That service would sit outside Claude/OpenAI, and it is a build-phase decision.

### F3 — Emergency (P2, built early)

**Story:** If something goes wrong, Mom taps the red 紧急 button from any screen and immediately sees four huge buttons.

| Button | Behavior |
|---|---|
| **拨打 911** (Call 911) | Starts a 911 call (iOS shows one confirm tap). The screen shows and can **play aloud** an English script: "I don't speak English. I speak Mandarin. My address is ___." Most US 911 centers can bring in a phone interpreter, so the script tells her to say **"Mandarin."** |
| **打电话给 Alex** (Call Alex) | Calls Alex immediately. |
| **发短信给 Alex** (Text Alex) | Opens a prefilled message in Chinese with her current location link attached. She only has to tap send. |
| **我的医疗卡** (My medical card) | Shows her insurance card (front/back photos), policy number, insurer phone, emergency contact, and medical info (conditions, medications, allergies, doctor). Has a **"show to staff"** English view. |

Location sharing
- **Always-on sharing with Alex** is set up once through iOS's built-in Find My location sharing. It is the most reliable option, needs no app running, and Alex can see her location anytime.
- **Send my location now** sends a one-tap snapshot with an address in English and Chinese.
- Tapping 紧急 also **notifies Alex** with her location (build-phase: how alerts reach Alex).

Requirements
- The emergency screen, medical card and script work **fully offline**. Calls work with no data.
- Medical and insurance info is stored **on the device only**, encrypted. Alex edits it during setup.
- A home address card shows the address in large English to hand to a driver or stranger.
- There is a monthly "practice drill" mode so Mom can rehearse without calling anyone.

Acceptance
- Every emergency action is reachable in **2 taps or fewer** from any screen.
- Everything except the call itself works in airplane mode.

### F4 — Ride agent (P3)

**Story:** Mom taps 叫车, picks where she wants to go, and 小A gets her a car. She sees in Chinese which car to look for, with a screenshot, and gets updates as it arrives.

Flow (decision: **agent books, Alex approves**)
1. Mom taps 叫车. Her current location is the pickup.
2. She picks a destination from **saved places** (photo + Chinese name, set up by Alex, e.g. 家 Home, 超市 Supermarket, 公园 Park) or says it in Chinese.
3. 小A sends Alex a request: who, from where, to where, and the price estimate. **Alex approves with one tap.**
4. The agent books the ride on **Alex's Uber account**.
5. Mom gets a Chinese ride card with car make, color, **license plate (huge)**, driver name and photo, ETA, a **screenshot of the trip**, and live updates ("司机还有2分钟到" — "Driver arrives in 2 minutes", "司机到了" — "Driver has arrived").
6. A safety reminder to **check the plate before getting in**, plus an English card to show the driver with the destination address.
7. She can cancel or call Alex at any step.

Implementation paths (to decide in build, in order of preference)
- **A. Uber's official third-party rides API / Uber MCP server for AI agents.** Uber now offers a partner API, including an MCP server meant for agent booking. Access requires Uber's approval and may not be granted to a personal project. **Action: apply early.**
- **B. Browser agent on Uber's website,** signed in as Alex. A screenshot comes naturally from this path. It is fragile: bot checks, 2FA and UI changes. Check Uber's terms before relying on it.
- **C. Fallback.** Alex's approval opens Uber on his phone, prefilled as a ride for someone else, and Alex books manually. Mom still gets the car details in 小A if Alex forwards them.

Waymo: Waymo has no public booking API and books through its own app, so it is **out of v1**. Revisit if Uber offers Waymo rides in the area.

Acceptance
- Car details reach Mom within **60 seconds** of Alex approving (paths A/B).
- The plate shown to Mom matches the booked car 100% of the time.
- If Alex doesn't respond in 5 minutes, Mom is told in Chinese and offered "call Alex."

---

## 5. Alex's side (companion)

Minimal surface, form TBD in the build (an "Alex mode" in the same app, or a separate lightweight app or web page):
- Receive and approve ride requests (one tap).
- Receive emergency alerts with her location.
- Receive "Ask Alex" forwards from F1b.
- Edit saved places, contacts, home address, medical/insurance card, and personal context for F1b.
- See lesson progress and struggling phrases. Set the reminder time and pass bar.
- Remote config, so Mom never sees settings.

---

## 6. Non-functional requirements

### Responsiveness targets
| Interaction | Target |
|---|---|
| Any tap → visible feedback | < 100 ms |
| App launch → home | < 1 s |
| Camera overlay (F1a) | First translation < 1 s, tracks the camera smoothly |
| Ask (F1b) | Answer starts < 2 s |
| Interpreter (F1c) | Translated speech starts ~1.5–2 s after the speaker pauses |
| Coach feedback (F2) | < 1.5 s |
| Emergency (F3) | ≤ 2 taps from anywhere; offline |
| Ride details (F4) | < 60 s after approval |

### Reliability
- F1a, F3 and lesson content work offline.
- F1b, F1c, F2 scoring and F4 need data, and each shows a clear offline message with a fallback.
- Network calls retry automatically with a calm "still working" state from the mascot.
- Crash-free sessions are at least 99.5% during the field test.

### Privacy and security
- No API keys in the app binary. Calls go through a small backend Alex controls (architecture in build).
- Medical, insurance and contact data stays on the device, encrypted, and is never sent to an AI model.
- Location is shared only with Alex.
- Audio is not stored, except optionally her lesson attempts for progress review, which Alex can turn off.

### Cost
- Interpreter: two translation sessions at about $0.034/min each, plus source transcription at about $0.017/min each — roughly $0.10 per minute of conversation, so 30 min/day ≈ $3/day.
- Other per-use costs (vision Q&A, coach) are estimated in the build phase, with a monthly budget cap and alert to Alex.

---

## 7. Recommended models and APIs (candidates; final picks in build)

| Feature | Primary candidate | Why | Fallback |
|---|---|---|---|
| F1a overlay | Apple Vision + Apple Translation framework (on-device) | Only option fast enough for per-frame overlay; offline | — |
| F1b ask | Claude Sonnet 5.5 (vision) | Strong image understanding and Chinese writing | Claude Haiku 5.5 for speed; GPT vision model |
| F1b voice input | gpt-realtime-whisper (streaming) | Low-latency streaming transcription | Apple on-device speech recognition |
| F1c interpreter | gpt-realtime-translate | Purpose-built live speech translation; Chinese and English are both output languages | gpt-realtime-2 with interpreter prompt |
| F2 coach voice | gpt-realtime-2 | Native speech-to-speech with reasoning, interruptions, tool calls | — |
| F2 scoring | gpt-realtime-2 judgment | Simplest | Dedicated pronunciation-assessment API |
| F2 curriculum | Claude Opus 5.5 (authored offline, reviewed by Alex) | Quality content, generated once | — |
| F4 booking | Uber 3P rides API / Uber MCP | Official, reliable, returns trip details | Browser agent; manual |

---

## 8. Build plan

| Milestone | Scope | Notes |
|---|---|---|
| M0 Foundation | Xcode project, design system (mascot, colors, type, Chinese copy), home shell, backend skeleton | **Enroll in the Apple Developer Program now.** Without it, apps installed by cable expire after 7 days. |
| M1 Safety + Look | F3 Emergency, F1a camera overlay | F3 pulled forward: small, offline, safety-critical |
| M2 Ask + Interpreter | F1b, F1c | Benchmark models on real photos and conversations |
| M3 Coach | F2 curriculum + lesson loop + Alex progress view | Pronunciation scorer decision here |
| M4 Rides | F4 + Alex approval flow | Path depends on Uber's response to the API application |
| M5 Field test | Mom uses it daily for a week; fix and polish | Watch her use it without helping |

### Decisions for the build phase (architecture)
1. Native SwiftUI app (assumed) and minimum iOS version.
2. Backend for API keys, Alex notifications and approvals: hosting and stack.
3. Form of Alex's side (same app vs. separate).
4. Final model per feature after benchmarks.
5. F1c two-way routing design.
6. F2 pronunciation scoring approach.
7. F4 booking path (A/B/C).
8. Data storage and what (if anything) syncs to Alex.

---

## 9. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Uber API access not granted for a personal project | F4 can't be fully automated | Apply early; browser agent (B) or manual fallback (C) |
| LLM pronunciation scoring too lenient or too harsh | Coach feels unfair or useless | Test with Mom's real attempts in M3; add a dedicated scorer if needed |
| Interpreter picks up its own voice or crosstalk | Garbled translations | Echo cancellation, mute mic during playback, AirPods option |
| Mom's iPhone is older | Slow overlay, missing on-device features | Confirm model now; set a minimum iOS version |
| No data plan or weak signal outside | Cloud features fail | US eSIM with data; offline fallbacks for F1a and F3 |
| Cost creep from always-on interpreter | Surprise bills | Silence prompt, monthly cap, alert to Alex |
| Mom finds it confusing | She stops using it | Six tiles max, mascot guidance, M5 field test before her visit gets busy |

---

## 10. Decisions log

| Date | Decision |
|---|---|
| 2026-10-13 | Rides: agent books on Alex's Uber account **after Alex approves** each ride. |
| 2026-10-13 | Build setup: Alex has a Mac with Xcode; no Apple Developer account yet. Enroll before installing on Mom's phone. |
| 2026-10-13 | Chinese: **Simplified**. |
| 2026-10-13 | Mom's English: **total beginner** (doesn't read the alphabet yet). Curriculum starts from spoken survival phrases. |
| 2026-10-13 | Waymo out of scope for v1. |
| 2026-10-13 | **v1 has no server: rides and alerts go by text message.** Mom's app texts Alex her location, destination and a pre-filled Uber link; Alex books Uber ("ride for someone else") and sends her the car details in Chinese from Alex mode. In-app ride card and automatic alerts wait for a backend (CloudKit or a small server). |
| 2026-10-13 | **API keys live in the iPhone Keychain**, entered once in Alex mode (long-press 小A, optional PIN). Not in the code. |
| 2026-10-13 | Native **SwiftUI, iOS 18+**, Swift 5 language mode. Project at `~/Documents/xiao-a`; builds go to Xcode's default DerivedData because iCloud-synced Documents breaks code signing. |
| 2026-10-13 | Look (F1a): **VisionKit live text + Apple Translation**, fully on-device. Alex downloads the offline language pack in setup. |
| 2026-10-13 | Ask (F1b): **claude-sonnet-5-5** with photo; Mandarin voice input via Apple speech recognition. |
| 2026-10-13 | Interpreter (F1c): **two gpt-realtime-translate sessions** (→ English, → Chinese), each with gpt-realtime-whisper source transcripts. A session's speech is played only when the speaker used the language it translates from; the mic sends silence while the phone talks. |
| 2026-10-13 | Learn (F2): pass = **on-device English speech recognition understands each word** (≥75% normal, 100% strict). One-line Chinese tips from **claude-haiku-5-5** (offline fallback). 174-phrase curriculum in 29 units, in survival order; role-play deferred. |
| 2026-10-13 | Emergency (F3): the 911 button opens a one-screen helper ("say *Mandarin*") before calling, so a 911 call is 3 taps + iOS's confirm. Deliberate exception to the 2-tap target. |
| 2026-10-14 | **Simulator demo mode** for review: Debug builds in the simulator load sample details and play scripted versions of Look, Ask, the interpreter and the coach's microphone (marked 模拟器示例). Never on a real iPhone. Clickable prototype from real simulator screens: https://claude.ai/artifact/62hoBetBKxBxsghoNUmeaL |
| 2026-10-14 | Interpreter supports **German** as well as English for the other person (Alex's request). Same two-session design with the partner session's output set to German; the other person's half of the screen and Mom's two ready-made phrases switch to German. More languages are a small change (gpt-realtime-translate has 13 output languages). |
| 2026-10-14 | Interpreter **always uses the iPhone's own speaker and mic**, even with AirPods connected, so the other person hears every translation (spoken and shown). Each line's translated speech is kept so either side can hear it again: **Play again / Nochmal anhören** on the other person's half, 再听一遍 on Mom's. This replaces the earlier "optional AirPods" idea. |
| 2026-10-14 | Setup includes **Find My location sharing** from Mom's iPhone to Alex's, since the Emergency screen tells her Alex can always see where she is. |
| 2026-10-14 | Real-iPhone finding: the interpreter's mic went quiet after a few seconds. Two fixes: Apple's voice-processing mic mode is off (on the iPhone it handed the app empty audio; echo is still handled by muting the mic while the phone talks), and **silent audio from gpt-realtime-translate is skipped**: the service streams audio constantly, silence included, and playing it kept the mic muted. The waveform now moves only when the mic actually hears someone. |
| 2026-10-14 | Real-iPhone finding: Mom heard her own sentence repeated in Mandarin. The Chinese-output session "translates" her Chinese into Chinese, and a 2.5 s "play it anyway if no transcript yet" fallback let it through. Now **the interpreter never plays speech it can't place**: each line waits for its source transcript (or the other session's verdict on the same speech), anything still unplaced after 8 s is dropped, a pause of 1.2 s in the source speech starts a new line so a reply right after the phone talks isn't merged into the previous speaker's line, and an **echo guard** drops speech that matches what the phone itself just said. |
| 2026-10-14 | Mock sessions on the iPhone: gpt-realtime-translate **often sends no source transcript for the other person's English** (the translation still arrives), while Mom's Chinese is transcribed within ~0.2 s. Replies were being dropped. Now a translation without a transcript is placed by timing: it is the other person's reply unless Chinese was heard around then or the phone was talking when it began (the mic is off while the phone talks). Replies can start ~1 s later than Mom's translations. Debug log in the Xcode console: one summary per sentence ("[XA] …"). |
| 2026-10-14 | Interpreter redesign (Alex's request): **Mom starts and ends each conversation.** Start screen (language + big 开始对话 button) → conversation (one big 结束对话, no 紧急 beside it) → 说完了 screen with the transcript, 再开始 and 回首页. Replaces "starts listening as soon as the screen opens". |
| 2026-10-14 | Voiceprint speaker detection (FluidAudio) and a voice clone of Mom are **parked** (`Parked/voiceprint-interpreter/`); focus is conversation quality first. |
| 2026-10-14 | Look (F1a) upgrade: fine print and context. Live mode keeps instant on-device translation and adds **in-context translation by Claude Haiku** once the camera is steady; **放大** (2× zoom); **定住画面** = careful full-resolution OCR + **Claude Sonnet with the photo**. Replies use numbered plain lines instead of JSON, which broke on quotes. |
| 2026-10-14 | Interpreter (F1c) **rebuilt turn by turn**, because simultaneous translation sometimes mistranslated and missed what either side said (gpt-realtime-translate often sent no transcript for the other person, so replies couldn't be placed). Now: one transcription stream for everyone → language decides who spoke → **Claude Sonnet translates the whole sentence with conversation context** → natural OpenAI voice, one turn at a time, mic muted while the phone talks. Trade-off: ~1.5–2.5 s per turn instead of near-simultaneous, in exchange for accuracy and never losing a line. Console log per line: `pause->text`, `text->translation`, `translation->voice`. |
| 2026-10-14 | Code is in git (local repo, author Alex Qi). GitHub push to **xelastarburst/xiao-a** (private) once that repo exists and the Claude GitHub app can reach it. |
| 2026-10-14 | Interpreter sound (Alex's testing): **voice choice per side** in Alex mode › Interpreter voices (Marin, Cedar, Coral, Sage, Shimmer, Ash, Ballad, Verse, each with a sample; default Marin): one voice for Mom's words to others, one for others' words to Mom. **Louder:** audio session in default mode (media loudness, never Bluetooth), translated speech lifted up to ~10 dB and evened out without clipping, and the voice is told to project. **Less sensitive to the room:** the phone learns the room's background level and only sends the transcriber sound ≥ ~7 dB louder than it (with 0.3 s lead-in so first syllables survive); server VAD threshold 0.5 → 0.6. Console logs the room level every 15 s for tuning. |
| 2026-10-14 | Learn (F2) fixes from Alex's testing. **Mic:** a stale "cancelled" callback from the previous press switched off the new recording, so tries came back empty and were never compared; callbacks are now tied to their own press, and Apple's server recognizer is used (the on-device English model is often missing on a Chinese iPhone). Each try is recorded; if Apple hears nothing, **OpenAI gpt-4o-transcribe** checks the recording. The retry card shows **我听到的是：…**. **Never stuck:** an empty try counts as a try (4 max), and **跳过这句** is always there. **More phrases:** the start screen adds **按场景练习**, all 29 everyday scenes (~175 phrases) as cards with progress; **再学几句新的** continues past the daily lesson; Alex can set up to 10 new phrases a day. |
| 2026-10-14 | Learn (F2) is **hands-free and patient** (Alex's request: slower, keep going until it matches). 小A reads the phrase slowly ("请跟我说"), then listens on its own: no button to hold. It waits for her to speak and ends the try after a 1.8 s pause. Not yet? A tip, the phrase again (word by word from the second try), and it listens again, **with no try limit**. 跳过这句 is always there, and suggested after 5 tries. The mic only opens once the phone is completely quiet, so it can't hear itself. It stops after two silent rounds and shows 开始跟读. Reading speed is in Alex mode (Normal / Slow / Very slow; default Slow). Root cause of "doesn't compare": on Mom's iPhone the listener's measurement audio mode produced **empty mic buffers**; it now uses default mode and a fresh audio engine per listen, and logs buffer counts. |
| 2026-10-15 | **Keys built into the app** so Mom's phone needs no typing: a phone with no key saved in Alex mode uses the keys in `XiaoA/BundledKeys.json`, a file that lives only on Alex's Mac (git ignores it). Alex chose this over a QR transfer or a key server. Trade-off: the keys sit inside the app as plain text; both phones share one bill, so each account gets a monthly spending cap. Alex mode › **Test keys** checks each key with a tiny real request; both passed on Alex's iPhone. Installs on Mom's iPhone 13 use Alex's free Apple account (cable install, re-run from Xcode every 7 days); the $99/year Developer Program would give 1-year installs and TestFlight. |
| 2026-10-20 | **Automated tests** (Alex's request: "bullet proof"): 119 unit tests (Swift Testing) + 8 UI tests, all passing on the iPhone simulator; run with Product › Test before each install. One regression test per bug already fixed; the lesson loop runs with a fake voice and scripted tries; nothing can dial, text or call 911 in a test. Live checks against Claude and OpenAI (keys, session settings, translation, voice) are opt-in (scheme variable `XIAOA_LIVE_API`). Writing the tests found and fixed six bugs: interpreter mic gate re-sending audio, a started reading being restarted after 3 s, "son's" heard as "sons" marked wrong, the mic hardware started on every lesson stop, SMS fallback cut at "&"/"#", and a voice lookup per sentence. Test plan and results: https://claude.ai/artifact/5Mvxh629GCydenE5SJC3zD |

## 11. Open questions

1. What iPhone model and iOS version does Mom have?
2. When does she arrive, and what's the target date for a first version on her phone?
3. Will she have a US phone number and data plan (e.g. eSIM)? This affects 911 callbacks, Uber driver contact, and every cloud feature.
4. App name and mascot: keep 小A ("Little Alex"), or something else?
5. How should alerts and ride approvals reach Alex: iPhone push, iMessage, or Slack?
6. Monthly API budget cap?

---

## Sources
- [OpenAI — Advancing voice intelligence with new models in the API (May 2026)](https://openai.com/pt-BR/index/advancing-voice-intelligence-with-new-models-in-the-api/)
- [gpt-realtime-translate output languages and pricing](https://vantaige.io/blog/gpt-realtime-translate-70-language-voice-agent-2026)
- [Uber Developers — 3P Demand Rides API introduction](https://developer.uber.com/docs/third-party-rides-demand-v1/introduction)
- [Uber Developers — privileged scopes for ride requests](https://developer.uber.com/docs/scopes)
- [API Evangelist — Waymo has no public developer API](https://providers.apievangelist.com/providers/waymo/)
- [AppleInsider — iOS 26 Live Translation and developer API](https://appleinsider.com/articles/25/06/09/apple-brings-live-translation-to-imessage-phone-calls-and-more)
- [Pronunciation assessment with GPT-4o (Interspeech paper)](https://arxiv.org/html/2503.11229v1)
