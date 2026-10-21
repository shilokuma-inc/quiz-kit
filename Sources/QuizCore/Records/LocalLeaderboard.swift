import Foundation

/// 1 プレイ分の記録
///
/// 将来項目を足すときは Optional にする。`Codable` の自動生成は、JSON に無い Optional の項目を nil として読むため、
/// 古いバージョンが保存した記録もそのまま読める。
public struct ScoreRecord: Codable, Equatable, Sendable {
    public let score: Int
    /// 達成日時
    public let achievedAt: Date

    public init(score: Int, achievedAt: Date) {
        self.score = score
        self.achievedAt = achievedAt
    }
}

/// 端末の中だけのランキング（自分との競争）
///
/// 枠（モード × 難易度など、アプリが決めるキー）ごとに、スコアの上位 `maxRecordCount` 件を達成日時つきで UserDefaults に持つ。
/// 自己ベストはその 1 位。サーバーを持たずに「自己ベスト更新」「過去の自分のトップ 10」を出したいアプリ向け。
/// 全員と競うランキングが要るときは QuizGameCenter と併用する。
public struct LocalLeaderboard {
    /// 枠ごとに残す件数
    public let maxRecordCount: Int

    private let userDefaults: UserDefaults
    private let now: () -> Date

    public init(maxRecordCount: Int = 10, userDefaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.maxRecordCount = maxRecordCount
        self.userDefaults = userDefaults
        self.now = now
    }

    /// 枠の記録（スコアの高い順。同点は先に出した記録が上）
    public func records(forKey key: String) -> [ScoreRecord] {
        guard let data = userDefaults.data(forKey: key),
              let records = try? Self.decoder.decode([ScoreRecord].self, from: data)
        else {
            // 読めない（壊れている）ときは空として扱い、プレイを止めない
            return []
        }
        return records
    }

    /// 自己ベスト（1 位のスコア）。まだ記録が無ければ nil
    public func bestScore(forKey key: String) -> Int? {
        records(forKey: key).first?.score
    }

    /// スコアを現在時刻で記録し、自己ベストを更新したかを返す
    ///
    /// 0 点は記録しない（0 点を「NEW RECORD!」として祝わないため。初回は 1 点以上なら更新になる）。
    /// 同点は自己ベストの更新としない。上位 `maxRecordCount` 件に入らないスコアは残らない。
    @discardableResult
    public func record(score: Int, forKey key: String) -> Bool {
        guard score > 0 else { return false }
        // 読み込みから書き込みまでを 1 つの操作にし、同じ枠への保存が重なっても先の記録を消さない
        Self.saveLock.lock()
        defer { Self.saveLock.unlock() }
        var records = records(forKey: key)
        let previousBest = records.first?.score ?? 0
        // 同点の記録の後ろに入れる（先に出した記録を上にする）
        let index = records.firstIndex { $0.score < score } ?? records.endIndex
        records.insert(ScoreRecord(score: score, achievedAt: now()), at: index)
        records = Array(records.prefix(maxRecordCount))
        if let data = try? Self.encoder.encode(records) {
            userDefaults.set(data, forKey: key)
        }
        return score > previousBest
    }

    /// 枠の記録を消す
    public func removeRecords(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }

    private static let saveLock = NSLock()

    /// 日時は UNIX 時間（秒）で保存する。`JSONEncoder` の既定（2001 年起点）より他の仕組みから読みやすい
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
