# Parked: simultaneous interpreter (2026-10-14)

The first 翻译官 engine: two always-on OpenAI gpt-realtime-translate sessions (→ English/German,
→ Chinese) on one microphone, with the speaker guessed from each session's source transcript.
Replaced by the turn-by-turn engine because transcripts went missing (so speech was dropped or
misrouted) and translating mid-sentence hurt accuracy. Kept for comparison.

To try it again: copy InterpreterEngine.swift back to XiaoA/Features/Interpreter/
(TranslateSocket.swift is still in the app).
