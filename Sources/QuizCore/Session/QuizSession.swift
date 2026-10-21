import Foundation
import Observation

/// 1 問分の解答
public struct QuizAnswer<Question: QuizQuestion>: Identifiable, Sendable {
    /// 解答した順（1 始まり）
    public let id: Int
    /// 何問目の解答か（0 始まり。`QuizSession.questions` の添字）
    public let questionIndex: Int
    public let question: Question
    public let choice: Question.Choice
    public let isCorrect: Bool
    /// 問題が表示されてから解答するまでの秒数
    public let elapsedSeconds: TimeInterval

    public init(
        id: Int,
        questionIndex: Int,
        question: Question,
        choice: Question.Choice,
        elapsedSeconds: TimeInterval
    ) {
        self.id = id
        self.questionIndex = questionIndex
        self.question = question
        self.choice = choice
        self.isCorrect = question.isCorrect(choice)
        self.elapsedSeconds = elapsedSeconds
    }
}

/// プレイが終わった理由
public enum QuizFinishReason: Sendable, Equatable {
    /// 全問に答えた
    case completed
    /// 制限時間が尽きた
    case timeUp
    /// 途中でやめた（`QuizSession.quit()`）
    case quit
}

/// `QuizSession` が知らせる出来事。効果音・触覚・計測など、画面の外の処理をここにつなぐ
public enum QuizSessionEvent<Question: QuizQuestion>: Sendable {
    /// 解答した。`scoreDelta` はその解答でのスコアの増減（タイムアタックの誤答では負）
    case answered(QuizAnswer<Question>, scoreDelta: Int)
    /// 誤答で残り時間を減らした
    case timePenalty(seconds: Int)
    /// 次の問題に進んだ（0 始まりの添字）
    case advanced(to: Int)
    /// 残り時間が 1 秒減った。`isFinalCountdown` は終盤（`QuizRules.finalCountdownSeconds` 以下）か
    case tick(remainingSeconds: Int, isFinalCountdown: Bool)
    /// プレイが終わった。1 プレイにつき 1 回だけ
    case finished(QuizFinishReason)
}

/// 1 プレイの進行
///
/// 出題・解答の受付・スコア・コンボ・制限時間・問題の補充・終わりの判定を持ち、画面は持たない。
/// 画面（標準の `QuizUI` でもアプリ独自のレイアウトでも）はこのクラスを観察して描き、`answer(_:)` を呼ぶだけでよい。
///
/// ```swift
/// let session = QuizSession(questions: questions, rules: .timeAttack(seconds: 30))
/// session.onEvent = { event in
///     if case .answered(let answer, _) = event { SoundPlayer.play(answer.isCorrect ? .correct : .wrong) }
/// }
/// session.start()
/// ```
@MainActor
@Observable
public final class QuizSession<Question: QuizQuestion> {
    // MARK: - 設定

    public let rules: QuizRules
    /// 残りが少なくなったときに足す問題を作る。nil なら補充せず、最後の問題に答えたら終わる
    @ObservationIgnored private let refill: (() -> [Question])?
    @ObservationIgnored private let scheduler: any QuizScheduler
    /// 出来事の通知先
    @ObservationIgnored public var onEvent: ((QuizSessionEvent<Question>) -> Void)?

    // MARK: - 状態

    /// 出題（補充すると後ろに増える）
    public private(set) var questions: [Question]
    /// 表示中の問題（0 始まり）。解き終えたあとは最後の問題のまま
    public private(set) var currentIndex: Int = 0
    /// 解答の記録（解答順）
    public private(set) var answers: [QuizAnswer<Question>] = []
    /// スコア・コンボ・正解数
    public private(set) var score: ScoreCalculator
    /// 残り時間（秒）。制限時間が無ければ 0
    public private(set) var remainingSeconds: Int
    /// 終わった理由。プレイ中は nil
    public private(set) var finishReason: QuizFinishReason?
    /// 解答後、次の問題へ進むのを待っている間は true
    public private(set) var isWaitingToAdvance = false
    /// 誤答後の入力ロック中は true
    public private(set) var isInputLocked = false
    /// 表示中の問題が出た時刻。解答時間の計測の起点
    @ObservationIgnored public private(set) var questionStartDate: Date

    @ObservationIgnored private var timer: QuizSchedulerTimer?

    /// - Parameters:
    ///   - questions: 出題。空にはしない
    ///   - rules: 進め方
    ///   - refill: 残りが `rules.refillThreshold` 以下になったら呼び、返した問題を後ろに足す。タイムアタックのように問題数を決めないプレイで使う
    ///   - scheduler: 時刻と予約。テストで差し替える
    public init(
        questions: [Question],
        rules: QuizRules = .practice,
        refill: (() -> [Question])? = nil,
        scheduler: (any QuizScheduler)? = nil
    ) {
        precondition(!questions.isEmpty, "出題が空")
        let scheduler = scheduler ?? LiveQuizScheduler()
        self.questions = questions
        self.rules = rules
        self.refill = refill
        self.scheduler = scheduler
        self.score = ScoreCalculator(rule: rules.scoringRule, configuration: rules.scoring)
        self.remainingSeconds = rules.timeLimitSeconds ?? 0
        self.questionStartDate = scheduler.now()
    }

    // MARK: - 読み取り

    /// 表示中の問題
    public var currentQuestion: Question {
        questions[currentIndex]
    }

    /// 終わったか
    public var isFinished: Bool {
        finishReason != nil
    }

    /// 解答を受け付けるか。終わったあと・次の問題へ進むのを待っている間・誤答後のロック中は受け付けない
    public var acceptsAnswer: Bool {
        !isFinished && !isWaitingToAdvance && !isInputLocked
    }

    /// 制限時間のあるプレイか
    public var hasTimeLimit: Bool {
        rules.timeLimitSeconds != nil
    }

    /// 残り時間が終盤か。0 秒は終わりなので含めない
    public var isInFinalCountdown: Bool {
        hasTimeLimit && (1...max(1, rules.finalCountdownSeconds)).contains(remainingSeconds)
    }

    // MARK: - 操作

    /// プレイを始める。制限時間があればカウントダウンを始め、表示中の問題の解答時間を測り始める
    public func start() {
        questionStartDate = scheduler.now()
        guard hasTimeLimit, timer == nil, !isFinished else { return }
        timer = scheduler.repeating(every: 1.0) { [weak self] in
            self?.tick()
        }
    }

    /// カウントダウンを止める。画面が消えるときに呼ぶ
    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// 表示中の問題に `choice` で答える。受け付けなかったら nil
    @discardableResult
    public func answer(_ choice: Question.Choice) -> QuizAnswer<Question>? {
        guard acceptsAnswer else { return nil }
        let question = currentQuestion
        let answer = QuizAnswer(
            id: answers.count + 1,
            questionIndex: currentIndex,
            question: question,
            choice: choice,
            elapsedSeconds: scheduler.now().timeIntervalSince(questionStartDate)
        )
        answers.append(answer)
        let delta = score.submit(
            isCorrect: answer.isCorrect,
            difficultyFactor: question.scoreFactor,
            elapsedTime: answer.elapsedSeconds
        )
        onEvent?(.answered(answer, scoreDelta: delta))

        if !answer.isCorrect {
            lockInputIfNeeded()
        }

        if rules.advanceDelay > 0 {
            isWaitingToAdvance = true
            scheduler.schedule(after: rules.advanceDelay) { [weak self] in
                guard let self else { return }
                isWaitingToAdvance = false
                advance()
            }
        } else {
            advance()
        }

        if !answer.isCorrect {
            applyMissTimePenaltyIfNeeded()
        }
        return answer
    }

    /// 残り時間を 1 秒進める。通常は `start()` のタイマーが呼ぶ
    public func tick() {
        guard hasTimeLimit, !isFinished else { return }
        if remainingSeconds > 1 {
            remainingSeconds -= 1
            onEvent?(.tick(remainingSeconds: remainingSeconds, isFinalCountdown: isInFinalCountdown))
        } else {
            remainingSeconds = 0
            finish(.timeUp)
        }
    }

    /// 途中でやめる。全問に答え終えていれば（最後の解説の表示中など）解き終えたものとして扱う
    public func quit() {
        guard !isFinished else { return }
        let completesPlay = refill == nil && answers.count >= questions.count
        finish(completesPlay ? .completed : .quit)
    }

    /// 途中の状態から始める。撮影モードやプレビューで、何問か解いた画面を作るときに使う
    ///
    /// `answers` の順に解答し直し（スコアも同じ計算で求める）、`remainingSeconds` を設定する。
    /// `isFinished` なら解き終えた状態にする。出来事（`onEvent`）は知らせない。
    public func restore(answeredChoices: [(Question.Choice, elapsedSeconds: TimeInterval)], remainingSeconds: Int? = nil, isFinished: Bool = false) {
        for (choice, elapsed) in answeredChoices where answers.count < questions.count {
            let question = questions[answers.count]
            let answer = QuizAnswer(
                id: answers.count + 1,
                questionIndex: answers.count,
                question: question,
                choice: choice,
                elapsedSeconds: elapsed
            )
            answers.append(answer)
            score.submit(isCorrect: answer.isCorrect, difficultyFactor: question.scoreFactor, elapsedTime: elapsed)
        }
        currentIndex = min(answers.count, questions.count - 1)
        if let remainingSeconds {
            self.remainingSeconds = remainingSeconds
        }
        if isFinished {
            currentIndex = max(0, answers.count - 1)
            finishReason = .completed
        }
    }

    // MARK: - 内部

    private func advance() {
        guard !isFinished else { return }
        if currentIndex < questions.count - 1 {
            currentIndex += 1
            questionStartDate = scheduler.now()
            refillIfNeeded()
            onEvent?(.advanced(to: currentIndex))
        } else {
            finish(.completed)
        }
    }

    private func refillIfNeeded() {
        guard let refill, currentIndex >= questions.count - rules.refillThreshold else { return }
        questions.append(contentsOf: refill())
    }

    private func lockInputIfNeeded() {
        guard rules.missInputLockDuration > 0 else { return }
        isInputLocked = true
        scheduler.schedule(after: rules.missInputLockDuration) { [weak self] in
            self?.isInputLocked = false
        }
    }

    private func applyMissTimePenaltyIfNeeded() {
        guard hasTimeLimit, rules.missTimePenaltySeconds > 0, !isFinished else { return }
        let before = remainingSeconds
        remainingSeconds = max(0, remainingSeconds - rules.missTimePenaltySeconds)
        onEvent?(.timePenalty(seconds: before - remainingSeconds))
        if remainingSeconds == 0 {
            finish(.timeUp)
        }
    }

    private func finish(_ reason: QuizFinishReason) {
        guard !isFinished else { return }
        stop()
        finishReason = reason
        onEvent?(.finished(reason))
    }
}
