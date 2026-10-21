import Foundation

/// 1 プレイの進め方
///
/// 練習・タイムアタック・デイリーのような「モード」はアプリごとに名前も数も違うので Kit では持たず、
/// アプリはモードからこのルールを作って `QuizSession` に渡す。
public struct QuizRules: Sendable, Equatable {
    /// 制限時間（秒）。nil なら時間無制限で、全問に答えたら終わる
    public var timeLimitSeconds: Int?
    /// 誤答で減らす残り時間（秒）。制限時間が無ければ使わない
    public var missTimePenaltySeconds: Int
    /// 誤答後に解答を受け付けない時間（秒）。当てずっぽうの連打を防ぐ
    public var missInputLockDuration: TimeInterval
    /// 解答してから次の問題へ進むまでの待ち時間（秒）。解説を読ませたいときに使う。待っている間の時間は次の問題の解答時間に含めない
    public var advanceDelay: TimeInterval
    /// 残り時間がこの秒数以下になったら終盤とみなす（`QuizSessionEvent.tick` の `isFinalCountdown`）
    public var finalCountdownSeconds: Int
    /// 問題の補充（`QuizSession` の `refill`）を、残りの問題がこの数以下になったら行う
    public var refillThreshold: Int
    /// スコアの計算ルール
    public var scoringRule: ScoringRule
    /// スコアの係数
    public var scoring: ScoringConfiguration

    public init(
        timeLimitSeconds: Int? = nil,
        missTimePenaltySeconds: Int = 0,
        missInputLockDuration: TimeInterval = 0,
        advanceDelay: TimeInterval = 0,
        finalCountdownSeconds: Int = 5,
        refillThreshold: Int = 3,
        scoringRule: ScoringRule = .practice,
        scoring: ScoringConfiguration = .standard
    ) {
        self.timeLimitSeconds = timeLimitSeconds
        self.missTimePenaltySeconds = missTimePenaltySeconds
        self.missInputLockDuration = missInputLockDuration
        self.advanceDelay = advanceDelay
        self.finalCountdownSeconds = finalCountdownSeconds
        self.refillThreshold = refillThreshold
        self.scoringRule = scoringRule
        self.scoring = scoring
    }

    /// 決まった問題数を時間無制限で解く
    public static let practice = QuizRules()

    /// 制限時間内にできるだけ多く解く。誤答で時間と点を減らし、短時間だけ入力を止める
    public static func timeAttack(seconds: Int) -> QuizRules {
        QuizRules(
            timeLimitSeconds: seconds,
            missTimePenaltySeconds: 2,
            missInputLockDuration: 0.5,
            scoringRule: .timeAttack
        )
    }
}
