# Helferlein

The German edition of 小A, for an elderly German speaker living in the US. Same design and code
as 小A (branch `german` of the same repository), without the English lessons.

- **Lesen**: point the camera at English, read it in German (on-device, refined by Claude).
- **Fragen**: ask anything in German, with or without a photo; answers in short German (Sie).
- **Dolmetscher**: turn-by-turn interpreter, German ↔ English or German ↔ Chinese.
- **Fahrt**: send a ride request to her family; they book it and text her the car details.
- **Notfall**: 911 helper (say "German"), call or text her family with her location, medical card.

Setup (Settings, English): long-press the little orange on the home screen for 2 seconds.
Her family's name and number go there; until then the app says "Ihre Familie".

Build: open `Helferlein.xcodeproj`. Bundle ID `com.alexqi.helferlein`. Keys come from
`XiaoA/BundledKeys.json` (git-ignored, copied from 小A on the Mac) or the Keychain.
Tests: Product › Test on an iPhone simulator (82 unit tests, 7 UI tests).
