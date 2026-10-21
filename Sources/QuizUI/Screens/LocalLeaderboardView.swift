import QuizCore
import SwiftUI

/// 端末の中のランキング（`LocalLeaderboard`）の一覧。順位・スコア・達成日を出す
public struct LocalLeaderboardView: View {
    @Environment(\.quizTheme) private var theme
    private let records: [ScoreRecord]

    public init(records: [ScoreRecord]) {
        self.records = records
    }

    public var body: some View {
        if records.isEmpty {
            Text("No records yet", bundle: .module)
                .font(theme.bodyFont)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: theme.spacing / 2) {
                ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                    HStack {
                        Text(verbatim: "\(index + 1)")
                            .font(theme.numberFont)
                            .foregroundStyle(index == 0 ? theme.accent : theme.secondaryText)
                            .frame(width: 40, alignment: .leading)
                        Text(verbatim: "\(record.score)")
                            .font(theme.numberFont)
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        Text(record.achievedAt, format: .dateTime.year().month().day())
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(.horizontal, theme.spacing)
                    .padding(.vertical, theme.spacing / 2)
                    .background(
                        RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                            .fill(theme.surface)
                    )
                }
            }
        }
    }
}
