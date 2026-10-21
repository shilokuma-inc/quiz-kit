import QuizCore
import SwiftUI

/// 標準の結果画面。スコア・正解数・最大コンボ・自己ベストの更新を出し、下にアプリのボタン（もう一度・ホームへ など）を並べる
public struct QuizResultView<Question: QuizQuestion, Actions: View>: View {
    @Environment(\.quizTheme) private var theme
    private let session: QuizSession<Question>
    private let isNewRecord: Bool
    private let bestScore: Int?
    private let actions: Actions

    /// - Parameters:
    ///   - isNewRecord: 自己ベストを更新したか（`LocalLeaderboard.record` の戻り値）
    ///   - bestScore: これまでの自己ベスト。nil なら出さない
    public init(
        session: QuizSession<Question>,
        isNewRecord: Bool = false,
        bestScore: Int? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.session = session
        self.isNewRecord = isNewRecord
        self.bestScore = bestScore
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: theme.spacing) {
            Spacer()
            if session.finishReason == .timeUp {
                Text("Time's up!", bundle: .module)
                    .font(theme.questionFont)
                    .foregroundStyle(theme.secondaryText)
            }
            if isNewRecord {
                Text("NEW RECORD!", bundle: .module)
                    .font(theme.questionFont)
                    .foregroundStyle(theme.accent)
            }
            Text(verbatim: "\(session.score.totalScore)")
                .font(theme.titleFont)
                .foregroundStyle(theme.primaryText)
            Grid(alignment: .leading, horizontalSpacing: theme.spacing, verticalSpacing: theme.spacing / 2) {
                GridRow {
                    Text("Correct", bundle: .module)
                    Text(verbatim: "\(session.score.correctCount) / \(session.answers.count)")
                }
                GridRow {
                    Text("Max combo", bundle: .module)
                    Text(verbatim: "\(session.score.maxCombo)")
                }
                if let bestScore {
                    GridRow {
                        Text("Best", bundle: .module)
                        Text(verbatim: "\(bestScore)")
                    }
                }
            }
            .font(theme.bodyFont)
            .foregroundStyle(theme.secondaryText)
            Spacer()
            actions
        }
        .padding(theme.spacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
    }
}
