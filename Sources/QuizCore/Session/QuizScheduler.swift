import Foundation

/// `QuizSession` が時刻を読み、待ち時間とカウントダウンを予約する先
///
/// 実機では `LiveQuizScheduler` を使い、テストでは時刻と予約を手で進める実装に差し替える。
@MainActor
public protocol QuizScheduler: AnyObject {
    /// 現在時刻。解答時間の計測に使う
    func now() -> Date
    /// `delay` 秒後に一度だけ `action` を呼ぶ
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void)
    /// `interval` 秒ごとに `action` を呼ぶ。戻り値を `cancel()` すると止まる
    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> QuizSchedulerTimer
}

/// `QuizScheduler.repeating` が返す、止められるタイマー
@MainActor
public protocol QuizSchedulerTimer: AnyObject {
    func cancel()
}

/// メインスレッドの `Timer` と `DispatchQueue` を使う `QuizScheduler`
@MainActor
public final class LiveQuizScheduler: QuizScheduler {
    public init() {}

    public func now() -> Date {
        Date()
    }

    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { action() }
        }
    }

    public func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> QuizSchedulerTimer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        // スクロールなどのトラッキング中でもカウントダウンを止めない
        RunLoop.main.add(timer, forMode: .common)
        return LiveTimer(timer: timer)
    }

    private final class LiveTimer: QuizSchedulerTimer {
        private let timer: Timer

        init(timer: Timer) {
            self.timer = timer
        }

        func cancel() {
            timer.invalidate()
        }
    }
}
