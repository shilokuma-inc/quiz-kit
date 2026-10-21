import Foundation

/// コンボの段階。段階が上がるたびに演出を一段ずつ強くするために使う
///
/// 既定の区切りは、倍率の上限（2.0 倍）に届く 11 コンボを最終段階（MAX）にしている。
public enum ComboStage: Int, Comparable, CaseIterable, Sendable {
    /// 1〜2 コンボ（0 もここに含める）
    case normal
    /// 3〜5 コンボ
    case good
    /// 6〜10 コンボ
    case great
    /// 11 コンボ〜
    case max

    /// Good が始まるコンボ数
    public static let goodMinimumCombo = 3
    /// Great が始まるコンボ数
    public static let greatMinimumCombo = 6
    /// MAX が始まるコンボ数
    public static let maxMinimumCombo = 11

    public init(combo: Int) {
        switch combo {
        case Self.maxMinimumCombo...:
            self = .max
        case Self.greatMinimumCombo...:
            self = .great
        case Self.goodMinimumCombo...:
            self = .good
        default:
            self = .normal
        }
    }

    public static func < (lhs: ComboStage, rhs: ComboStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// コンボが `oldCombo` から `newCombo` に変わったとき、段階が上がったか
    public static func didStageUp(from oldCombo: Int, to newCombo: Int) -> Bool {
        ComboStage(combo: newCombo) > ComboStage(combo: oldCombo)
    }

    /// Great の中での進み具合（6 コンボで 0、10 コンボで 1）。演出の強さを線形に上げるのに使う
    public static func greatProgress(combo: Int) -> Double {
        let steps = Double(maxMinimumCombo - 1 - greatMinimumCombo)
        return Swift.min(1, Swift.max(0, Double(combo - greatMinimumCombo) / steps))
    }
}
