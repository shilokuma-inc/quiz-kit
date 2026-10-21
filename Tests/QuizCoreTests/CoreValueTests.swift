import Foundation
import Testing
@testable import QuizCore

struct ScoreCalculatorTests {
    @Test func コンボ倍率と速度ボーナス() {
        var calculator = ScoreCalculator()
        calculator.submit(isCorrect: true, difficultyFactor: 1.5, elapsedTime: 0.5)
        // 150 + 速度 50
        #expect(calculator.totalScore == 200)
        calculator.submit(isCorrect: true, difficultyFactor: 1.5, elapsedTime: 3.5)
        // round(150 × 1.1) = 165 + 速度 25
        #expect(calculator.lastSubmission == ScoreBreakdown(correctPoints: 150, comboBonus: 15, speedBonus: 25))
        #expect(calculator.maxCombo == 2)
    }

    @Test func タイムアタックの誤答は減点するが0未満にしない() {
        var calculator = ScoreCalculator(rule: .timeAttack)
        calculator.submit(isCorrect: true, difficultyFactor: 1.0, elapsedTime: 0)
        #expect(calculator.totalScore == 100)
        #expect(calculator.submit(isCorrect: false, difficultyFactor: 1.0, elapsedTime: 0) == -100)
        #expect(calculator.totalScore == 0)
        #expect(calculator.currentCombo == 0)
    }

    @Test func コンボの段階() {
        #expect(ComboStage(combo: 2) == .normal)
        #expect(ComboStage(combo: 3) == .good)
        #expect(ComboStage(combo: 6) == .great)
        #expect(ComboStage(combo: 11) == .max)
        #expect(ComboStage.didStageUp(from: 5, to: 6))
        #expect(!ComboStage.didStageUp(from: 6, to: 7))
    }
}

struct SplitMix64Tests {
    /// 参照実装（Vigna の splitmix64.c）と同じ列になること。デイリーの出題を凍結する土台なので、変わったら必ず落とす
    @Test func 参照実装と同じ列() {
        var generator = SplitMix64(seed: 1_234_567)
        let values = (0..<5).map { _ in generator.next() }
        #expect(values == [
            6_457_827_717_110_365_317,
            3_203_168_211_198_807_973,
            9_817_491_932_198_370_423,
            4_593_380_528_125_082_431,
            16_408_922_859_458_223_821
        ])
    }

    @Test func 偏りなく範囲内を選ぶ() {
        var generator = SplitMix64(seed: 9)
        for _ in 0..<1000 {
            #expect((0..<7).contains(generator.nextIndex(below: 7)))
        }
        #expect(generator.shuffled(Array(0..<10)).sorted() == Array(0..<10))
    }

    @Test func FNV1a() {
        #expect(StableSeed.fnv1a("") == 0xcbf2_9ce4_8422_2325)
        #expect(StableSeed.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
    }
}

struct LocalLeaderboardTests {
    private func makeDefaults() -> UserDefaults {
        let name = "LocalLeaderboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func 上位だけを残し自己ベストの更新を返す() {
        let defaults = makeDefaults()
        let leaderboard = LocalLeaderboard(maxRecordCount: 3, userDefaults: defaults, now: { Date(timeIntervalSince1970: 100) })
        #expect(!leaderboard.record(score: 0, forKey: "k"))
        #expect(leaderboard.record(score: 10, forKey: "k"))
        #expect(!leaderboard.record(score: 10, forKey: "k"))
        #expect(leaderboard.record(score: 30, forKey: "k"))
        #expect(!leaderboard.record(score: 20, forKey: "k"))
        #expect(!leaderboard.record(score: 5, forKey: "k"))
        #expect(leaderboard.records(forKey: "k").map(\.score) == [30, 20, 10])
        #expect(leaderboard.bestScore(forKey: "k") == 30)
        #expect(leaderboard.records(forKey: "other").isEmpty)
    }

    @Test func 保存形式() throws {
        let defaults = makeDefaults()
        LocalLeaderboard(userDefaults: defaults, now: { Date(timeIntervalSince1970: 100) }).record(score: 7, forKey: "k")
        let data = try #require(defaults.data(forKey: "k"))
        #expect(String(decoding: data, as: UTF8.self) == #"[{"achievedAt":100,"score":7}]"#)
    }

    @Test func 日ごとの記録() {
        struct Record: Codable, Equatable {
            let correct: Int
        }
        let store = DayKeyedRecordStore<Record>(recordsKey: "daily", userDefaults: makeDefaults())
        store.save(Record(correct: 3), dayKey: "2026-10-02")
        store.save(Record(correct: 5), dayKey: "2026-10-01")
        store.save(Record(correct: 7), dayKey: "2026-10-02")
        #expect(store.record(dayKey: "2026-10-02") == Record(correct: 7))
        #expect(store.allRecords() == [Record(correct: 5), Record(correct: 7)])
    }
}

struct QuizDayTests {
    @Test func 日付キーの読み書き() {
        #expect(QuizDay(dayKey: "2026-10-01") == QuizDay(year: 2026, month: 10, day: 1))
        #expect(QuizDay(dayKey: "2026-02-30") == nil)
        #expect(QuizDay(dayKey: "2026-+1-01") == nil)
        #expect(QuizDay(year: 2026, month: 3, day: 9).dayKey == "2026-03-09")
    }

    @Test func 日数の計算() {
        let launch = QuizDay(year: 2026, month: 10, day: 7)
        #expect(launch.dayNumber(since: launch) == 1)
        #expect(QuizDay(year: 2026, month: 11, day: 1).dayNumber(since: launch) == 26)
        #expect(QuizDay(year: 2026, month: 12, day: 31).adding(days: 1) == QuizDay(year: 2027, month: 1, day: 1))
    }

    @Test func ストリーク() {
        let today = QuizDay(year: 2026, month: 10, day: 10)
        let days = [8, 9, 3, 4, 5, 6].map { QuizDay(year: 2026, month: 10, day: $0) }
        let streak = QuizStreak(completedDays: days, today: today)
        // 今日はまだでも昨日まで続いていれば切れていない
        #expect(streak.current == 2)
        #expect(streak.longest == 4)
        #expect(QuizStreak(completedDays: days, today: today.adding(days: 1)).current == 0)
    }
}
