import SwiftUI

/// Live glowing status orb indicating user voice transmission (Channel / Whisper / Shout).
public struct SpeakingOrbView: View {
    public let isTalking: Bool
    public var talkingState: TalkingState = .passive
    public var size: CGFloat = 10

    public init(isTalking: Bool, talkingState: TalkingState = .passive, size: CGFloat = 10) {
        self.isTalking = isTalking
        self.talkingState = talkingState
        self.size = size
    }

    private var activeColor: Color {
        switch talkingState {
        case .whisper:
            return .cyan
        case .shout:
            return .orange
        case .talking, .passive:
            return .green
        }
    }

    public var body: some View {
        Circle()
            .fill(isTalking ? activeColor : Color.secondary.opacity(0.35))
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(isTalking ? activeColor.opacity(0.8) : Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .glassEffect(
                .regular.tint(isTalking ? activeColor.opacity(0.3) : nil).interactive(),
                in: .circle
            )
            .shadow(
                color: isTalking ? activeColor.opacity(0.9) : .clear,
                radius: isTalking ? (size >= 10 ? 5 : 4) : 0
            )
            .scaleEffect(isTalking ? 1.15 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isTalking)
    }
}
