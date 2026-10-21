import Foundation
import Testing
@testable import QuizCore

/// 時刻と予約を手で進める `QuizScheduler`
@MainActor
final class ManualScheduler: QuizScheduler {
    private(set) var current = Date(timeIntervalSince1970: 0)
    private var pending: [(fireAt: Date, action: @MainActor () -> Void)] = []
    private(set) var repeatingTimers: [ManualTimer] = []

    func now() -> Date { current }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        pending.append((current.addingTimeInterval(delay), action))
    }

    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> QuizSchedulerTimer {
        let timer = ManualTimer(action: action)
        repeatingTimers.append(timer)
        return timer
    }

    /// 時刻を進め、その間に予約した処理を順に呼ぶ（カウントダウンは呼ばない。`session.tick()` で進める）
    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
        let due = pending.filter { $0.fireAt <= current }
        pending.removeAll { $0.fireAt <= current }
        due.forEach { $0.action() }
    }

    final class ManualTimer: QuizSchedulerTimer {
        let action: @MainActor () -> Void
        private(set) var isCancelled = false

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }
    }
}

/// 2 択の問題。`answer` が正解
struct TwoChoiceQuestion: QuizQuestion, Equatable {
    let id: Int
    let answer: Bool
    var scoreFactor: Double = 1.0

    var choices: [Bool] { [false, true] }

    func isCorrect(_ choice: Bool) -> Bool {
        choice == answer
    }
}

@MainActor
struct QuizSessionTests {
    private func questions(_ count: Int) -> [TwoChoiceQuestion] {
        (1...count).map { TwoChoiceQuestion(id: $0, answer: $0.isMultiple(of: 2)) }
    }

    @Test func 全問に答えると終わる() {
        let scheduler = ManualScheduler()
        let session = QuizSession(questions: questions(3), scheduler: scheduler)
        var events: [String] = []
        session.onEvent = { event in
            if case .finished(let reason) = event { events.append("finished:\(reason)") }
        }

        session.answer(false)
        session.answer(true)
        #expect(session.currentIndex == 2)
        #expect(!session.isFinished)
        // 3 問目の正解は false なので、ここだけ間違える
        session.answer(true)

        #expect(session.finishReason == .completed)
        #expect(session.currentIndex == 2)
        #expect(session.answers.count == 3)
        #expect(session.score.correctCount == 2)
        #expect(events == ["finished:completed"])
        // 終わったあとは受け付けない
        #expect(session.answer(true) == nil)
    }

    @Test func 解答時間は問題が出てから測る() {
        let scheduler = ManualScheduler()
        let session = QuizSession(questions: questions(2), scheduler: scheduler)
        session.start()
        scheduler.advance(by: 2.5)
        let answer = session.answer(false)
        #expect(answer?.elapsedSeconds == 2.5)
        scheduler.advance(by: 1)
        #expect(session.answer(true)?.elapsedSeconds == 1)
    }

    @Test func 待ち時間の間は次の問題に進まず受け付けない() {
        let scheduler = ManualScheduler()
        var rules = QuizRules.practice
        rules.advanceDelay = 1.5
        let session = QuizSession(questions: questions(2), rules: rules, scheduler: scheduler)

        session.answer(false)
        #expect(session.isWaitingToAdvance)
        #expect(session.currentIndex == 0)
        #expect(session.answer(true) == nil)

        scheduler.advance(by: 1.5)
        #expect(!session.isWaitingToAdvance)
        #expect(session.currentIndex == 1)
        // 解説を見ている間の時間は次の問題の解答時間に入らない
        scheduler.advance(by: 0.5)
        #expect(session.answer(true)?.elapsedSeconds == 0.5)
    }

    @Test func 待ち時間のあいだにやめても全問答えていれば解き終えた扱い() {
        let scheduler = ManualScheduler()
        var rules = QuizRules.practice
        rules.advanceDelay = 1.5
        let session = QuizSession(questions: questions(1), rules: rules, scheduler: scheduler)
        session.answer(false)
        session.quit()
        #expect(session.finishReason == .completed)
    }

    @Test func 途中でやめる() {
        let session = QuizSession(questions: questions(3), scheduler: ManualScheduler())
        session.answer(false)
        session.quit()
        #expect(session.finishReason == .quit)
    }

    @Test func タイムアタックは時間切れで終わる() {
        let scheduler = ManualScheduler()
        let session = QuizSession(questions: questions(3), rules: .timeAttack(seconds: 3), scheduler: scheduler)
        var ticks: [Int] = []
        session.onEvent = { event in
            if case .tick(let remaining, _) = event { ticks.append(remaining) }
        }
        session.start()
        #expect(scheduler.repeatingTimers.count == 1)

        session.tick()
        session.tick()
        #expect(session.remainingSeconds == 1)
        session.tick()
        #expect(session.remainingSeconds == 0)
        #expect(session.finishReason == .timeUp)
        #expect(ticks == [2, 1])
        #expect(scheduler.repeatingTimers[0].isCancelled)
    }

    @Test func タイムアタックの誤答は時間を減らし入力を止める() {
        let scheduler = ManualScheduler()
        let session = QuizSession(questions: questions(5), rules: .timeAttack(seconds: 30), scheduler: scheduler)
        var penalties: [Int] = []
        session.onEvent = { event in
            if case .timePenalty(let seconds) = event { penalties.append(seconds) }
        }

        session.answer(true) // 1 問目の正解は false
        #expect(session.remainingSeconds == 28)
        #expect(penalties == [2])
        // 誤答でも次の問題には進む
        #expect(session.currentIndex == 1)
        #expect(session.isInputLocked)
        #expect(session.answer(true) == nil)

        scheduler.advance(by: 0.5)
        #expect(!session.isInputLocked)
        #expect(session.answer(true) != nil)
    }

    @Test func 誤答で残り時間が尽きたらその場で終わる() {
        let session = QuizSession(questions: questions(5), rules: .timeAttack(seconds: 2), scheduler: ManualScheduler())
        session.answer(true)
        #expect(session.remainingSeconds == 0)
        #expect(session.finishReason == .timeUp)
    }

    @Test func 残りが少なくなったら補充する() {
        var refillCount = 0
        let session = QuizSession(
            questions: questions(4),
            rules: .timeAttack(seconds: 60),
            refill: {
                refillCount += 1
                return (1...4).map { TwoChoiceQuestion(id: 100 + $0, answer: false) }
            },
            scheduler: ManualScheduler()
        )
        session.answer(false) // index 1。残り 4 - 1 = 3 で補充
        #expect(refillCount == 1)
        #expect(session.questions.count == 8)
        session.answer(true)
        #expect(refillCount == 1)
    }

    @Test func 問題ごとの難易度係数でスコアを計算する() {
        let session = QuizSession(
            questions: [TwoChoiceQuestion(id: 1, answer: true, scoreFactor: 2.0)],
            scheduler: ManualScheduler()
        )
        session.answer(true)
        // 100 × 2.0 + 速度ボーナス 50
        #expect(session.score.totalScore == 250)
    }

    @Test func 途中の状態から始める() {
        let session = QuizSession(questions: questions(4), scheduler: ManualScheduler())
        var notified = false
        session.onEvent = { _ in notified = true }
        session.restore(answeredChoices: [(false, 1.8), (false, 1.8)], remainingSeconds: 42)
        #expect(session.currentIndex == 2)
        #expect(session.score.correctCount == 1)
        #expect(session.remainingSeconds == 42)
        #expect(!session.isFinished)
        #expect(!notified)

        let finished = QuizSession(questions: questions(2), scheduler: ManualScheduler())
        finished.restore(answeredChoices: [(false, 1), (true, 1)], isFinished: true)
        #expect(finished.finishReason == .completed)
        #expect(finished.currentIndex == 1)
    }
}
