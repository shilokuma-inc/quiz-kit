import Foundation

/// スコアの計算ルール
public enum ScoringRule: Sendable, Equatable {
    /// 誤答の減点なし・速度ボーナスは常に付く
    case practice
    /// 誤答で減点・速度ボーナスは一定のコンボから
    case timeAttack
}

/// スコアの係数。既定値は prime-pick で調整した値
public struct ScoringConfiguration: Sendable, Equatable {
    /// 正解 1 問あたりの基礎点
    public var basePoints: Int = 100
    /// コンボ 1 段階あたりの倍率の増分
    public var comboMultiplierStep: Double = 0.1
    /// コンボ倍率の上限
    public var maxComboMultiplier: Double = 2.0
    /// 速度ボーナスの上限点
    public var maxSpeedBonus: Int = 50
    /// この秒数以内に解答すると速度ボーナスが満点になる
    public var fullSpeedBonusSeconds: TimeInterval = 1.0
    /// この秒数以上かかると速度ボーナスが 0 になる
    public var zeroSpeedBonusSeconds: TimeInterval = 6.0
    /// タイムアタックの誤答で減点する点の、`基礎点 × 難易度係数` に対する倍率
    public var timeAttackMissPenaltyFactor: Double = 2.0
    /// タイムアタックで速度ボーナスが付き始めるコンボ数
    public var timeAttackSpeedBonusMinimumCombo: Int = 3

    public init() {}

    public static let standard = ScoringConfiguration()
}

/// クイズのスコア計算
///
/// 1 問あたりの獲得点は次の式で求める。
///
///     獲得点 = round(基礎点 × 難易度係数 × コンボ倍率) + 速度ボーナス
///
/// 不正解の場合はコンボがリセットされる。ルール（`ScoringRule`）によって次の違いがある。
///
/// - 練習: 不正解の獲得点は 0。速度ボーナスは常に付く
/// - タイムアタック: 不正解で `基礎点 × 難易度係数 × 減点倍率` を減点する（スコアは 0 未満にならない）。
///   速度ボーナスは一定のコンボ以上のときだけ付く
///
/// 難易度係数はアプリの難易度から決めて `difficultyFactor` で渡す（`QuizQuestion.scoreFactor`）。
public struct ScoreCalculator: Sendable, Equatable {
    /// 適用するスコアルール
    public let rule: ScoringRule
    /// 係数
    public let configuration: ScoringConfiguration

    /// 合計スコア
    public private(set) var totalScore: Int = 0
    /// 現在の連続正解数
    public private(set) var currentCombo: Int = 0
    /// このプレイ中の最大コンボ
    public private(set) var maxCombo: Int = 0
    /// 正解数
    public private(set) var correctCount: Int = 0
    /// 獲得点・減点の内訳の累計
    public private(set) var breakdown = ScoreBreakdown()
    /// 直前の 1 問の増減の内訳。まだ解答していなければ nil
    public private(set) var lastSubmission: ScoreBreakdown?

    public init(rule: ScoringRule = .practice, configuration: ScoringConfiguration = .standard) {
        self.rule = rule
        self.configuration = configuration
    }

    /// 1 問分の解答を反映し、その問題でのスコアの増減を返す
    ///
    /// タイムアタックの誤答では負の値を返す。スコアが 0 で止まった場合は、実際に減った分だけを返す。
    @discardableResult
    public mutating func submit(isCorrect: Bool, difficultyFactor: Double, elapsedTime: TimeInterval) -> Int {
        guard isCorrect else {
            currentCombo = 0
            let deducted = min(totalScore, missPenalty(difficultyFactor: difficultyFactor))
            totalScore -= deducted
            breakdown.penalty = ScoreBreakdown.addingClamped(breakdown.penalty, deducted)
            lastSubmission = ScoreBreakdown(penalty: deducted)
            return -deducted
        }

        currentCombo += 1
        maxCombo = max(maxCombo, currentCombo)
        correctCount += 1

        let gained = pointsBreakdown(difficultyFactor: difficultyFactor, combo: currentCombo, elapsedTime: elapsedTime)
        breakdown.correctPoints = ScoreBreakdown.addingClamped(breakdown.correctPoints, gained.correctPoints)
        breakdown.comboBonus = ScoreBreakdown.addingClamped(breakdown.comboBonus, gained.comboBonus)
        breakdown.speedBonus = ScoreBreakdown.addingClamped(breakdown.speedBonus, gained.speedBonus)
        totalScore = ScoreBreakdown.addingClamped(totalScore, gained.total)
        lastSubmission = gained
        return gained.total
    }

    // MARK: - 計算

    /// 連続正解数に対応するコンボ倍率
    /// - Parameter combo: 1 始まりの連続正解数。1 連続目は 1.0 倍
    public func comboMultiplier(combo: Int) -> Double {
        guard combo > 1 else { return 1.0 }
        let raw = 1.0 + configuration.comboMultiplierStep * Double(combo - 1)
        return min(raw, configuration.maxComboMultiplier)
    }

    /// 経過時間に対応する速度ボーナス。満点の秒数から 0 点の秒数の間を線形に補間する
    public func speedBonus(elapsedTime: TimeInterval) -> Int {
        // NaN が渡された場合はボーナスなしとして扱う
        guard elapsedTime.isFinite else { return 0 }
        let full = configuration.fullSpeedBonusSeconds
        let zero = configuration.zeroSpeedBonusSeconds
        if elapsedTime <= full { return configuration.maxSpeedBonus }
        if elapsedTime >= zero { return 0 }

        let ratio = (zero - elapsedTime) / (zero - full)
        let bonus = (Double(configuration.maxSpeedBonus) * ratio).rounded()
        return min(configuration.maxSpeedBonus, max(0, Int(bonus)))
    }

    /// 正解 1 問あたりの獲得点を、正解点・コンボボーナス・速度ボーナスに分けたもの
    ///
    /// 正解点は `基礎点 × 難易度係数`、コンボボーナスはコンボ倍率を掛けて増えた分。丸めは倍率を掛けた後に 1 回だけ行う。
    public func pointsBreakdown(difficultyFactor: Double, combo: Int, elapsedTime: TimeInterval) -> ScoreBreakdown {
        let base = Double(configuration.basePoints) * difficultyFactor
        let correctPoints = Self.clampedInt(base)
        let pointsWithCombo = Self.clampedInt(base * comboMultiplier(combo: combo))
        let bonus = earnsSpeedBonus(combo: combo) ? speedBonus(elapsedTime: elapsedTime) : 0
        return ScoreBreakdown(
            correctPoints: correctPoints,
            comboBonus: max(0, pointsWithCombo - correctPoints),
            speedBonus: bonus
        )
    }

    /// 速度ボーナスが付くか
    /// - Parameter combo: この問題の正解を含めた連続正解数
    public func earnsSpeedBonus(combo: Int) -> Bool {
        switch rule {
        case .practice:
            return true
        case .timeAttack:
            return combo >= configuration.timeAttackSpeedBonusMinimumCombo
        }
    }

    /// 誤答 1 問あたりの減点（正の値）。練習は減点しないので 0
    public func missPenalty(difficultyFactor: Double) -> Int {
        switch rule {
        case .practice:
            return 0
        case .timeAttack:
            return Self.clampedInt(
                Double(configuration.basePoints) * difficultyFactor * configuration.timeAttackMissPenaltyFactor
            )
        }
    }

    /// Double から Int への変換でクラッシュしないよう、現実的な上限で丸めてから変換する
    static func clampedInt(_ value: Double) -> Int {
        Int(min(max(value.rounded(), 0), Double(Int.max / 2)))
    }
}

/// 獲得点・減点の内訳
public struct ScoreBreakdown: Sendable, Equatable {
    /// 正解点（`基礎点 × 難易度係数`）
    public var correctPoints: Int
    /// コンボ倍率によって増えた点
    public var comboBonus: Int
    /// 速度ボーナス
    public var speedBonus: Int
    /// 誤答で実際に減った点（正の値）。スコアが 0 で止まった分は含めない
    public var penalty: Int

    public init(correctPoints: Int = 0, comboBonus: Int = 0, speedBonus: Int = 0, penalty: Int = 0) {
        self.correctPoints = correctPoints
        self.comboBonus = comboBonus
        self.speedBonus = speedBonus
        self.penalty = penalty
    }

    /// 獲得点の合計から減点を引いたもの
    public var total: Int {
        Self.addingClamped(Self.addingClamped(correctPoints, comboBonus), speedBonus) - penalty
    }

    /// オーバーフローした場合は `Int.max` に張り付かせる加算
    static func addingClamped(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}
