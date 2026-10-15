# Parked: voiceprint interpreter (2026-10-14)

Mom records ~20 s once; the phone recognises her voice (FluidAudio, on-device) and sends her speech
only to the English/German session and everyone else's only to the Chinese session. Parked by Alex
to keep testing the transcript-based interpreter first. Never built or tested.

To un-park:
1. Copy InterpreterEngine.swift, InterpreterAudio.swift, InterpreterView.swift into XiaoA/Features/Interpreter/
   and AlexModeView.swift into XiaoA/Features/Alex/ (replacing the current ones).
2. Add the package: replace XiaoA.xcodeproj/project.pbxproj with the one here (keeps your signing team),
   or in Xcode: File > Add Package Dependencies > https://github.com/FluidInference/FluidAudio.git (0.17.7).
3. VoiceID.swift, SpeakerRouter.swift and VoiceEnrollmentView.swift are already in the app folder,
   wrapped in `#if canImport(FluidAudio)`, so they switch on by themselves once the package is added.
