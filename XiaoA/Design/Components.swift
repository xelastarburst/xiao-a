import SwiftUI

// MARK: - Button feel

/// Every tap squishes and buzzes right away, even when the real work takes longer.
struct Squish: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

extension View {
    /// The soft "chunky" card look from the mockups: a fill with a darker lip underneath.
    func chunky(_ fill: Color, depth: Color? = nil, radius: CGFloat = 28, border: Color? = nil) -> some View {
        background(
            ZStack {
                if let depth {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(depth).offset(y: 5)
                }
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
                if let border {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border, lineWidth: 3)
                }
            }
        )
    }

    func card(_ fill: Color = .white, radius: CGFloat = 26) -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
    }
}

// MARK: - Buttons

struct BigButton: View {
    var title: String
    var systemImage: String? = nil
    var fill: Color = Palette.persimmon
    var depth: Color? = Palette.persimmonDeep
    var foreground: Color = .white
    var border: Color? = nil
    var height: CGFloat = 72
    var fontSize: CGFloat = 26
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: fontSize * 0.95, weight: .bold))
                }
                Text(title).font(.xa(fontSize, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .chunky(fill, depth: depth, radius: height / 2, border: border)
        }
        .buttonStyle(Squish())
    }
}

struct SoftButton: View {
    var title: String
    var systemImage: String? = nil
    var fill: Color = .white
    var border: Color? = Palette.line
    var foreground: Color = Palette.ink
    var height: CGFloat = 56
    var fontSize: CGFloat = 20
    var action: () -> Void

    var body: some View {
        BigButton(title: title, systemImage: systemImage, fill: fill, depth: nil, foreground: foreground,
                  border: border, height: height, fontSize: fontSize, action: action)
    }
}

/// Round icon-only button with a spoken label for VoiceOver.
struct IconButton: View {
    var systemImage: String
    var label: String
    var fill: Color = Palette.cream
    var foreground: Color = Palette.ink
    var size: CGFloat = 60
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
        }
        .buttonStyle(Squish())
        .accessibilityLabel(label)
    }
}

// MARK: - Top bar

/// 返回 on the left, title in the middle, red 紧急 on the right — the same on every screen.
struct TopBar: View {
    var title: String
    var showEmergency = true
    var onDark = false
    var onBack: (() -> Void)? = nil

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 22, weight: .heavy))
                    Text("返回").font(.xa(22, .heavy))
                }
                .foregroundStyle(Palette.ink)
                .padding(.leading, 12).padding(.trailing, 18)
                .frame(height: 60)
                .background(Capsule().fill(Color.white.opacity(onDark ? 0.94 : 1)))
            }
            .buttonStyle(Squish())

            Spacer(minLength: 4)
            Text(title)
                .font(.xa(26, .heavy))
                .foregroundStyle(onDark ? .white : Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)

            if showEmergency {
                EmergencyPill()
            } else {
                Color.clear.frame(width: 106, height: 60)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

struct EmergencyPill: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        Button { app.go(.emergency(practice: false)) } label: {
            HStack(spacing: 6) {
                Image(systemName: "phone.fill").font(.system(size: 20, weight: .bold))
                Text("紧急").font(.xa(22, .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 60)
            .background(Capsule().fill(Palette.red))
        }
        .buttonStyle(Squish())
    }
}

// MARK: - Speech bubbles

struct MascotSays: View {
    var text: String
    var detail: String? = nil
    var mood: Mascot.Mood = .happy
    var mascotSize: CGFloat = 72
    var textSize: CGFloat = 24

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Mascot(mood: mood, size: mascotSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.xa(textSize, .heavy)).foregroundStyle(Palette.ink)
                if let detail {
                    Text(detail).font(.xa(19, .medium)).foregroundStyle(Palette.ink2)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6,
                                       bottomTrailingRadius: 22, topTrailingRadius: 22, style: .continuous)
                    .fill(.white)
            )
        }
    }
}

struct WarningNote: View {
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 22, weight: .bold))
            Text(text).font(.xa(19, .bold))
        }
        .foregroundStyle(Palette.warnInk)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.warnWash))
    }
}

// MARK: - Hold to talk

/// WeChat-style "按住 说话": press to start, release to stop.
struct HoldToTalkButton: View {
    var title: String = "按住 说话"
    var activeTitle: String = "松开 发送"
    var isActive: Bool
    var fill: Color = Palette.persimmon
    var depth: Color = Palette.persimmonDeep
    var height: CGFloat = 72
    var onStart: () -> Void
    var onEnd: () -> Void

    @State private var pressing = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "waveform" : "mic.fill")
                .font(.system(size: 26, weight: .bold))
                .symbolEffect(.variableColor.iterative, isActive: isActive)
            Text(isActive ? activeTitle : title).font(.xa(26, .heavy))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .chunky(isActive ? depth : fill, depth: isActive ? nil : depth, radius: height / 2)
        .scaleEffect(pressing ? 0.97 : 1)
        .contentShape(Capsule())
        // onPressingChanged also fires `false` when the press is interrupted (a system alert,
        // a phone call), so the button can never get stuck "recording".
        .onLongPressGesture(minimumDuration: 120, maximumDistance: 400, perform: {}, onPressingChanged: { isPressing in
            if isPressing && !pressing {
                pressing = true
                Haptics.tap()
                onStart()
            } else if !isPressing && pressing {
                pressing = false
                onEnd()
            }
        })
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Two-way toggle

/// Two big choices side by side. Replaces the system segmented control, whose text is too small for Mom.
struct BigToggle: View {
    var left: String
    var right: String
    @Binding var isRight: Bool

    var body: some View {
        HStack(spacing: 6) {
            option(left, selected: !isRight) { isRight = false }
            option(right, selected: isRight) { isRight = true }
        }
        .padding(5)
        .background(Capsule().fill(Palette.line.opacity(0.7)))
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Text(title)
                .font(.xa(20, .heavy))
                .foregroundStyle(selected ? Palette.ink : Palette.ink2)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(selected ? Color.white : Color.clear))
                .shadow(color: selected ? .black.opacity(0.08) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Misc

struct ScreenBackground: View {
    var color: Color = Palette.cream
    var body: some View { color.ignoresSafeArea() }
}

struct ErrorCard: View {
    var title: String
    var detail: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.xa(22, .heavy)).foregroundStyle(Palette.ink)
            Text(detail).font(.xa(19, .medium)).foregroundStyle(Palette.ink2)
            if let retry {
                SoftButton(title: "再试一次", systemImage: "arrow.clockwise", action: retry)
            }
        }
        .card()
    }
}
