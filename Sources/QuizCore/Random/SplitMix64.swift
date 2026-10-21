import Foundation

/// SplitMix64（Steele, Lea, Flood 2014）。状態 64bit の小さな PRNG で、同じシードからは常に同じ列を返す
///
/// デイリーチャレンジのように「どの端末・どの OS でも同じ出題」を守りたいときに使う。
/// `RandomNumberGenerator` には適合させない。適合させると標準ライブラリの `random(in:using:)`・`shuffled(using:)` に渡せてしまい、
/// それらの引き方は OS の更新で変わりうるため、出題が端末ごとにずれる。
/// 標準ライブラリと組み合わせたいときは `SeededRandomNumberGenerator` を使う。
public struct SplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    /// `0..<1` の一様な小数。上位 53bit をそのまま `Double` の仮数にする
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1p-53
    }

    /// `0..<upperBound` から偏りなく 1 つ選ぶ
    ///
    /// 単純な剰余は `2^64` が `upperBound` で割り切れない分だけ小さい値に偏るため、
    /// 端数にあたる `2^64 mod upperBound` 個の値を捨てて引き直す。
    public mutating func nextIndex(below upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound は 1 以上")
        let bound = UInt64(upperBound)
        let threshold = (0 &- bound) % bound
        while true {
            let value = next()
            if value >= threshold {
                return Int(value % bound)
            }
        }
    }

    /// `elements` を Fisher–Yates で並べ替えたもの。標準ライブラリの `shuffled` に依らないので、OS が変わっても同じ並びになる
    public mutating func shuffled<Element>(_ elements: [Element]) -> [Element] {
        var result = elements
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            result.swapAt(index, nextIndex(below: index + 1))
        }
        return result
    }
}

/// シードから決まった乱数列を作る `RandomNumberGenerator`
///
/// 撮影モードやテストで「撮り直しても同じ出題」にしたいときに使う。
/// 標準ライブラリのアルゴリズムと組み合わせるので、OS をまたいで同じ列になることまでは保証しない（それが要るなら `SplitMix64` を直接使う）。
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var source: SplitMix64

    public init(seed: UInt64) {
        source = SplitMix64(seed: seed)
    }

    public mutating func next() -> UInt64 {
        source.next()
    }
}

/// 文字列から、起動や端末に依らない 64bit のシードを作る
///
/// `hashValue` / `Hasher` は起動ごとに値が変わるため、シードには使えない。
public enum StableSeed {
    /// `string` の UTF-8 に対する FNV-1a（64bit）
    public static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
