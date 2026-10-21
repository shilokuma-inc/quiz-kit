import QuizCore
import SwiftUI

/// 選択肢の並べ方
public enum QuizChoiceLayout: Sendable, Equatable {
    /// 縦に 1 列
    case vertical
    /// 横に 1 列（2 択向け）
    case horizontal
    /// `columns` 列の格子（4 択を 2 × 2 にするなど）
    case grid(columns: Int)

    /// 選択肢の数に合った並べ方。2 択は横、3 択は縦、4 択以上は 2 列
    public static func automatic(choiceCount: Int) -> QuizChoiceLayout {
        switch choiceCount {
        case ...2:
            return .horizontal
        case 3:
            return .vertical
        default:
            return .grid(columns: 2)
        }
    }
}

/// 標準の出題画面
///
/// 上から「状況（進捗・スコア・残り時間）」「問題」「選択肢」を並べる。3 つの部品はそれぞれ ViewBuilder で差し替えられる。
/// - 問題（`prompt`）: 必ずアプリが描く。国旗の画像・都道府県の形・数字など
/// - 選択肢のラベル（`choiceLabel`）: 既定は `String(describing:)`。ボタンの形と正誤の色は `QuizChoiceButton` が持つ
/// - 状況（`status`）: 既定は `QuizStatusBar`
///
/// 部品の差し替えでは足りない（画面の構成そのものを変えたい）ときは、この画面を使わずに `QuizSession` を観察する画面を作る。
public struct QuizPlayView<Question: QuizQuestion, Prompt: View, ChoiceLabel: View, Status: View>: View {
    @Environment(\.quizTheme) private var theme
    private let session: QuizSession<Question>
    private let layout: QuizChoiceLayout?
    private let prompt: (Question) -> Prompt
    private let choiceLabel: (Question.Choice) -> ChoiceLabel
    private let status: (QuizSession<Question>) -> Status

    public init(
        session: QuizSession<Question>,
        layout: QuizChoiceLayout? = nil,
        @ViewBuilder prompt: @escaping (Question) -> Prompt,
        @ViewBuilder choiceLabel: @escaping (Question.Choice) -> ChoiceLabel,
        @ViewBuilder status: @escaping (QuizSession<Question>) -> Status
    ) {
        self.session = session
        self.layout = layout
        self.prompt = prompt
        self.choiceLabel = choiceLabel
        self.status = status
    }

    public var body: some View {
        VStack(spacing: theme.spacing) {
            status(session)

            prompt(session.currentQuestion)
                .font(theme.questionFont)
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(session.currentIndex)
                .transition(.opacity)

            choices
                .frame(maxHeight: .infinity)
        }
        .padding(theme.spacing)
        .background(theme.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: session.currentIndex)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }

    @ViewBuilder private var choices: some View {
        let question = session.currentQuestion
        switch layout ?? .automatic(choiceCount: question.choices.count) {
        case .vertical:
            VStack(spacing: theme.spacing / 2) { choiceButtons(question) }
        case .horizontal:
            HStack(spacing: theme.spacing / 2) { choiceButtons(question) }
        case .grid(let columns):
            Grid(horizontalSpacing: theme.spacing / 2, verticalSpacing: theme.spacing / 2) {
                ForEach(Array(stride(from: 0, to: question.choices.count, by: max(1, columns))), id: \.self) { start in
                    GridRow {
                        ForEach(Array(question.choices[start..<min(start + columns, question.choices.count)]), id: \.self) { choice in
                            button(for: choice, in: question)
                        }
                    }
                }
            }
        }
    }

    private func choiceButtons(_ question: Question) -> some View {
        ForEach(question.choices, id: \.self) { choice in
            button(for: choice, in: question)
        }
    }

    private func button(for choice: Question.Choice, in question: Question) -> some View {
        QuizChoiceButton(
            state: QuizChoiceState.of(choice, in: question, session: session),
            isEnabled: session.acceptsAnswer
        ) {
            session.answer(choice)
        } label: {
            choiceLabel(choice)
        }
    }
}

extension QuizPlayView where Status == QuizStatusBar<Question> {
    /// 状況の表示を標準（`QuizStatusBar`）にする版
    public init(
        session: QuizSession<Question>,
        layout: QuizChoiceLayout? = nil,
        @ViewBuilder prompt: @escaping (Question) -> Prompt,
        @ViewBuilder choiceLabel: @escaping (Question.Choice) -> ChoiceLabel
    ) {
        self.init(session: session, layout: layout, prompt: prompt, choiceLabel: choiceLabel) { session in
            QuizStatusBar(session: session)
        }
    }
}

extension QuizPlayView where Status == QuizStatusBar<Question>, ChoiceLabel == Text {
    /// 選択肢を文字で出す版
    public init(
        session: QuizSession<Question>,
        layout: QuizChoiceLayout? = nil,
        @ViewBuilder prompt: @escaping (Question) -> Prompt
    ) {
        self.init(session: session, layout: layout, prompt: prompt) { choice in
            Text(String(describing: choice))
        }
    }
}

extension QuizChoiceState {
    /// 表示中の問題に対する、選択肢 `choice` の状態
    ///
    /// 解答してから次の問題に進むまで（`QuizRules.advanceDelay` の間）、選んだ選択肢と正解に色を付ける。
    @MainActor
    public static func of<Question: QuizQuestion>(
        _ choice: Question.Choice,
        in question: Question,
        session: QuizSession<Question>
    ) -> QuizChoiceState {
        guard let last = session.answers.last, last.questionIndex == session.currentIndex else { return .idle }
        if last.choice == choice {
            return last.isCorrect ? .correct : .incorrect
        }
        if !last.isCorrect, question.isCorrect(choice) {
            return .revealedCorrect
        }
        return .dimmed
    }
}
