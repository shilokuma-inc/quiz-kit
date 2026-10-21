import QuizCore
import SwiftUI

/// 出題中の状況。問題数を決めたプレイは進捗（3 / 10）、制限時間のあるプレイは残り時間を出し、スコアとコンボを添える
public struct QuizStatusBar<Question: QuizQuestion>: View {
    @Environment(\.quizTheme) private var theme
    private let session: QuizSession<Question>
    private let showsScore: Bool
    private let showsCombo: Bool

    public init(session: QuizSession<Question>, showsScore: Bool = true, showsCombo: Bool = true) {
        self.session = session
        self.showsScore = showsScore
        self.showsCombo = showsCombo
    }

    public var body: some View {
        HStack {
            if session.hasTimeLimit {
                Label("\(session.remainingSeconds)", systemImage: "timer")
                    .foregroundStyle(session.isInFinalCountdown ? theme.incorrect : theme.primaryText)
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel(Text("Remaining \(session.remainingSeconds) seconds", bundle: .module))
            } else {
                Text(verbatim: "\(session.currentIndex + 1) / \(session.questions.count)")
                    .foregroundStyle(theme.primaryText)
            }
            Spacer()
            if showsCombo, session.score.currentCombo >= 2 {
                Text("\(session.score.currentCombo) combo", bundle: .module)
                    .foregroundStyle(theme.accent)
                    .transition(.scale.combined(with: .opacity))
            }
            if showsScore {
                Text(verbatim: "\(session.score.totalScore)")
                    .foregroundStyle(theme.primaryText)
                    .contentTransition(.numericText())
            }
        }
        .font(theme.numberFont)
        .animation(.snappy, value: session.score.totalScore)
        .animation(.snappy, value: session.score.currentCombo)
        .animation(.snappy, value: session.remainingSeconds)
    }
}
