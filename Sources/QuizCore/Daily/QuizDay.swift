import Foundation

/// デイリーチャレンジの 1 日。全員が同じ日に同じ問題を解くための「今日」を表す
///
/// - 「今日」は端末のタイムゾーンの 0 時で切り替える
/// - 年月日はグレゴリオ暦で数える。`Calendar.current` は和暦・タイ仏暦の端末で年がずれ、
///   `dayKey`（＝ 出題のシード）が他の端末と食い違うため使わない
public struct QuizDay: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// `2026-10-01` の形式から読み取る。存在しない日付（`2026-02-30` など）は nil
    public init?(dayKey: String) {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        let candidate = QuizDay(year: year, month: month, day: day)
        // `Int` は `+1`・`-01` のような符号付きも読めるため、正規形と一致するものだけを受け付ける（同じ日に別のキーを作らない）
        guard candidate.dayKey == dayKey else { return nil }
        // 正規化して元に戻らない日付（13 月・2 月 30 日など）は受け付けない
        guard let date = candidate.startDate(in: Self.utc),
              QuizDay(date: date, timeZone: Self.utc) == candidate
        else { return nil }
        self = candidate
    }

    /// `date` の瞬間に、`timeZone` の地域で何日か
    public init(date: Date, timeZone: TimeZone) {
        let components = Self.calendar(timeZone: timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0)
    }

    /// 端末の「今日」。時刻とタイムゾーンはテストのために差し替えられる
    public static func today(now: Date = Date(), timeZone: TimeZone = .current) -> QuizDay {
        QuizDay(date: now, timeZone: timeZone)
    }

    /// 記録や出題のシードに使うキー。`2026-10-01` の形式
    public var dayKey: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// 通し番号。`launchDay` を 1 とした経過日数（公開日より前は 0 以下）
    public func dayNumber(since launchDay: QuizDay) -> Int {
        days(since: launchDay) + 1
    }

    /// `days` 日後（負なら前）の日
    public func adding(days: Int) -> QuizDay {
        let calendar = Self.calendar(timeZone: Self.utc)
        guard let start = startDate(in: Self.utc),
              let moved = calendar.date(byAdding: .day, value: days, to: start)
        else { return self }
        return QuizDay(date: moved, timeZone: Self.utc)
    }

    /// `other` から何日経ったか（`other` より前なら負）
    public func days(since other: QuizDay) -> Int {
        let calendar = Self.calendar(timeZone: Self.utc)
        guard let start = other.startDate(in: Self.utc),
              let end = startDate(in: Self.utc)
        else { return 0 }
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// この日が `timeZone` の地域で始まる瞬間（0 時）
    public func startDate(in timeZone: TimeZone) -> Date? {
        Self.calendar(timeZone: timeZone).date(from: DateComponents(year: year, month: month, day: day))
    }

    public static func < (lhs: QuizDay, rhs: QuizDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// 日付の計算に使う暦。端末の設定に依らずグレゴリオ暦に固定する
    public static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// 日の加減算・日数の差に使うタイムゾーン。夏時間で 1 日が 23 / 25 時間になる地域の影響を受けないようにする
    private static let utc = TimeZone(identifier: "UTC")!
}

/// 続けて遊んだ日数（`🔥 12`）と最長記録
public struct QuizStreak: Equatable, Sendable {
    /// 現在のストリーク。今日か昨日に遊んでいて、そこから途切れずに続いている日数
    public let current: Int
    /// これまでで最も長く続いたストリーク
    public let longest: Int

    /// - Parameters:
    ///   - completedDays: 遊んだ（数える条件を満たした）日。順不同・重複可
    ///   - today: 端末の「今日」
    ///
    /// 今日まだ遊んでいなくても、昨日まで続いていればストリークは切れていない扱いにする（今日遊べば続く）。
    /// 端末の時計を戻して「今日」より後の日の記録がある場合も、最長には数え、現在のストリークには数えない。
    public init(completedDays: some Sequence<QuizDay>, today: QuizDay) {
        let days = Set(completedDays)

        let latest = days.contains(today) ? today : today.adding(days: -1)
        var current = 0
        var day = latest
        while days.contains(day) {
            current += 1
            day = day.adding(days: -1)
        }

        var longest = 0
        var run = 0
        var previous: QuizDay?
        for day in days.sorted() {
            if let previous, day.days(since: previous) == 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        self.current = current
        self.longest = max(longest, current)
    }
}
