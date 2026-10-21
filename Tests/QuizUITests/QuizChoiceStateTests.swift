import Foundation
import QuizCore
@testable import QuizUI
import Testing

/// 予約を呼ばない `QuizScheduler`。解答した問題を表示したままにする
@MainActor
private final class NoWaitScheduler: QuizScheduler {
    func now() -> Date { Date(timeIntervalSince1970: 0) }
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {}
    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> QuizSchedulerTimer {
        NoopTimer()
    }
}

@MainActor
private final class NoopTimer: QuizSchedulerTimer {
    func cancel() {}
}

@MainActor
struct QuizChoiceStateTests {
    private func makeSession() -> QuizSession<ChoiceQuestion<String, String>> {
        var rules = QuizRules.practice
        // 待ち時間の間は解答した問題を表示したままにする（予約は呼ばれない）
        rules.advanceDelay = 1
        return QuizSession(
            questions: [ChoiceQuestion(prompt: "日本", choices: ["東京", "大阪", "京都"], correctChoice: "東京")],
            rules: rules,
            scheduler: NoWaitScheduler()
        )
    }

    @Test("答える前はすべて通常") func idleBeforeAnswer() {
        let session = makeSession()
        let question = session.currentQuestion
        #expect(question.choices.map { QuizChoiceState.of($0, in: question, session: session) } == [.idle, .idle, .idle])
    }

    @Test("誤答すると選んだものと正解に色を付ける") func incorrectRevealsCorrect() {
        let session = makeSession()
        let question = session.currentQuestion
        session.answer("大阪")
        #expect(question.choices.map { QuizChoiceState.of($0, in: question, session: session) } == [.revealedCorrect, .incorrect, .dimmed])
    }

    @Test("正解すると選んだものだけ色を付ける") func correctHighlightsChosen() {
        let session = makeSession()
        let question = session.currentQuestion
        session.answer("東京")
        #expect(question.choices.map { QuizChoiceState.of($0, in: question, session: session) } == [.correct, .dimmed, .dimmed])
    }

    @Test("選択肢の数に合った並べ方") func automaticLayout() {
        #expect(QuizChoiceLayout.automatic(choiceCount: 2) == .horizontal)
        #expect(QuizChoiceLayout.automatic(choiceCount: 3) == .vertical)
        #expect(QuizChoiceLayout.automatic(choiceCount: 4) == .grid(columns: 2))
    }
}
