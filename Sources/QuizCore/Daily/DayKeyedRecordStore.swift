import Foundation

/// 1 日 1 件の記録を UserDefaults に保存する
///
/// 記録は `dayKey` をキーにした辞書を 1 つの JSON として 1 キーに保存する（1 日 1 件・1 件数百バイトなので、数年分でも小さい）。
/// 記録の中身（正解数・解答時間など）はアプリが決める。
public struct DayKeyedRecordStore<Record: Codable> {
    /// 保存に使うキー。形式を変えるときは別のキーにして、古いキーから移す
    public let recordsKey: String

    private let userDefaults: UserDefaults

    public init(recordsKey: String, userDefaults: UserDefaults = .standard) {
        self.recordsKey = recordsKey
        self.userDefaults = userDefaults
    }

    /// その日の記録。まだ無ければ nil
    public func record(dayKey: String) -> Record? {
        loadRecords()[dayKey]
    }

    /// すべての記録（`dayKey` の昇順）
    public func allRecords() -> [Record] {
        loadRecords().sorted { $0.key < $1.key }.map(\.value)
    }

    /// 記録を保存する。同じ `dayKey` の記録があれば置き換える
    public func save(_ record: Record, dayKey: String) {
        // 全件を読んで 1 件差し替えて書き戻すため、別の日の保存と重なると先の保存を消してしまう。
        // 読み込みから書き込みまでを、すべてのインスタンスで共有するロックで 1 つの操作にする
        dayKeyedRecordStoreLock.lock()
        defer { dayKeyedRecordStoreLock.unlock() }
        var records = loadRecords()
        records[dayKey] = record
        guard let data = try? LocalLeaderboard.encoder.encode(records) else { return }
        userDefaults.set(data, forKey: recordsKey)
    }

    /// 保存済みの記録。読めない（壊れている）ときは空として扱い、起動やプレイを止めない
    private func loadRecords() -> [String: Record] {
        guard let data = userDefaults.data(forKey: recordsKey),
              let records = try? LocalLeaderboard.decoder.decode([String: Record].self, from: data)
        else { return [:] }
        return records
    }
}

/// ジェネリック型は static な保存領域を持てないため、ロックはファイルの外に置く
private let dayKeyedRecordStoreLock = NSLock()
