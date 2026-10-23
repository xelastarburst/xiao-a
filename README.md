# Helferlein

The German edition of 小A, for an elderly German speaker living in the US. Same design and code
as 小A (this is branch `german`; 小A is on `main`), without the English lessons.

- **Lesen**: point the camera at English, read it in German (on-device, refined by Claude).
- **Fragen**: ask anything in German, with or without a photo; answers in short German (Sie).
- **Dolmetscher**: turn-by-turn interpreter, German ↔ English or German ↔ Chinese.
- **Fahrt**: send a ride request to her family; they book it and text her the car details.
- **Notfall**: 911 helper (say "German"), call or text her family with her location, medical card.

## Build

Open `Helferlein.xcodeproj` (Xcode 16 or later; iOS 18+). Bundle ID `com.alexqi.helferlein`.
The target, module and source folder are still named `XiaoA`, which keeps merges from `main`
simple.

API keys come from the iPhone's Keychain (Settings › API keys) or from
`XiaoA/BundledKeys.json`, which is git-ignored and copied from 小A on the Mac:

```json
{ "openai": "sk-…", "anthropic": "sk-ant-…" }
```

## Setup on her phone

Settings are in English: long-press the little orange on the home screen for 2 seconds.
Her name, home address, places, medical card and her family's name and number go there; until a
family name is entered the app says "Ihre Familie". Download the English–German translation
languages there too.

## Tests

Product › Test on an iPhone simulator: 82 unit tests and 7 UI tests. Fixes shared with 小A are
made on `main` and merged into this branch.
