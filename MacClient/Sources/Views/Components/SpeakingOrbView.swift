import SwiftUI

/// Live glowing Liquid Glass status orb indicating user voice transmission (Channel / Whisper / Shout).
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
            .frame(width: size, height: size)
            .glassEffect(
                .regular.tint(isTalking ? activeColor : .secondary.opacity(0.25)),
                in: .circle
            )
            .shadow(
                color: isTalking ? activeColor.opacity(0.85) : .clear,
                radius: isTalking ? 5 : 0
            )
            .animation(.easeInOut(duration: 0.15), value: isTalking)
    }
}
