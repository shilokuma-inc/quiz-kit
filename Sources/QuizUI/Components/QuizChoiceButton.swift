import SwiftUI

/// 選択肢ボタンの状態。解答直後に正解・不正解の色を見せるために使う
public enum QuizChoiceState: Sendable, Equatable {
    /// まだ答えていない
    case idle
    /// 選んで正解だった
    case correct
    /// 選んで不正解だった
    case incorrect
    /// 選ばなかった正解（不正解を選んだときに正解を示す）
    case revealedCorrect
    /// 選ばなかった不正解
    case dimmed
}

/// 標準の選択肢ボタン
public struct QuizChoiceButton<Label: View>: View {
    @Environment(\.quizTheme) private var theme
    private let state: QuizChoiceState
    private let isEnabled: Bool
    private let action: () -> Void
    private let label: Label

    public init(state: QuizChoiceState = .idle, isEnabled: Bool = true, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.state = state
        self.isEnabled = isEnabled
        self.action = action
        self.label = label()
    }

    public var body: some View {
        Button(action: action) {
            label
                .font(theme.choiceFont)
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 3)
                )
                .opacity(state == .dimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeOut(duration: 0.15), value: state)
    }

    private var fill: Color {
        switch state {
        case .idle, .dimmed:
            return theme.surface
        case .correct, .revealedCorrect:
            return theme.correct
        case .incorrect:
            return theme.incorrect
        }
    }

    private var foreground: Color {
        switch state {
        case .idle, .dimmed:
            return theme.primaryText
        case .correct, .incorrect, .revealedCorrect:
            return .white
        }
    }

    private var stroke: Color {
        switch state {
        case .idle, .dimmed:
            return theme.accent.opacity(0.4)
        case .correct, .revealedCorrect:
            return theme.correct
        case .incorrect:
            return theme.incorrect
        }
    }
}

extension QuizChoiceButton where Label == Text {
    public init(_ title: String, state: QuizChoiceState = .idle, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.init(state: state, isEnabled: isEnabled, action: action) { Text(title) }
    }
}
