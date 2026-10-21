import Foundation

/// データセット（1 行 1 件の表）から択一問題を作る
///
/// 問題を 1 問ずつ書かずに、「どの列を問題に、どの列を答えにするか」を決めて出題を作る。
/// たとえば国のデータセットから「国旗 → 国名」「国名 → 首都」の 2 種類のクイズが作れる。
/// 誤答の選択肢は同じデータセットのほかの行から引く。
///
/// ```swift
/// let generator = ChoiceQuestionGenerator(
///     items: countries,
///     choiceCount: 4,
///     prompt: \.flagImageName,
///     answer: \.name,
///     distractorGroup: \.region // 同じ地域の国を誤答にして難しくする（任意）
/// )
/// let questions = generator.makeQuestions(count: 10, using: &rng)
/// ```
public struct ChoiceQuestionGenerator<Item: Sendable, Prompt: Hashable & Sendable, Answer: Hashable & Sendable>: Sendable {
    /// 出題に使うデータ
    public let items: [Item]
    /// 選択肢の数（2 択なら 2）。正解を含む
    public let choiceCount: Int
    private let prompt: @Sendable (Item) -> Prompt
    private let answer: @Sendable (Item) -> Answer
    private let distractorGroup: (@Sendable (Item) -> AnyHashable)?
    private let scoreFactor: @Sendable (Item) -> Double
    /// 同じ問題を続けて出さないために覚えておく直近の問題数
    public let recentWindow: Int
    private var recentPrompts: [Prompt] = []

    /// - Parameters:
    ///   - items: 出題に使うデータ。答えが同じ行が複数あってもよい（誤答には答えが異なる行だけを使う）
    ///   - choiceCount: 選択肢の数。答えの種類がこれより少ないときは、ある分だけ並べる
    ///   - prompt: 問題として見せる値
    ///   - answer: 正解の値（選択肢に並ぶ値）
    ///   - distractorGroup: 指定すると、誤答を同じグループの行から優先して選ぶ（足りなければほかのグループから補う）
    ///   - scoreFactor: 行ごとの難易度係数。データの `difficulty` 列などから決める
    ///   - recentWindow: 直近に出した問題を避ける数
    public init(
        items: [Item],
        choiceCount: Int,
        prompt: @escaping @Sendable (Item) -> Prompt,
        answer: @escaping @Sendable (Item) -> Answer,
        distractorGroup: (@Sendable (Item) -> AnyHashable)? = nil,
        scoreFactor: @escaping @Sendable (Item) -> Double = { _ in 1.0 },
        recentWindow: Int = 5
    ) {
        precondition(choiceCount >= 2, "選択肢は 2 つ以上")
        self.items = items
        self.choiceCount = choiceCount
        self.prompt = prompt
        self.answer = answer
        self.distractorGroup = distractorGroup
        self.scoreFactor = scoreFactor
        self.recentWindow = recentWindow
    }

    /// `count` 問を作る。データが空なら空を返す
    ///
    /// 1 プレイの中で同じ行はなるべく出さない（行数より多く作るときは一巡してから重ねる）。
    public mutating func makeQuestions<Generator: RandomNumberGenerator>(
        count: Int,
        using generator: inout Generator
    ) -> [ChoiceQuestion<Prompt, Answer>] {
        guard !items.isEmpty, count > 0 else { return [] }
        var questions: [ChoiceQuestion<Prompt, Answer>] = []
        var deck: [Int] = []
        while questions.count < count {
            if deck.isEmpty {
                deck = freshIndices().shuffled(using: &generator)
            }
            let item = items[deck.removeLast()]
            questions.append(makeQuestion(for: item, using: &generator))
            remember(prompt(item))
        }
        return questions
    }

    /// 1 行分の問題。誤答は答えが異なる行から `choiceCount - 1` 個選び、正解とまとめて並べ替える
    public func makeQuestion<Generator: RandomNumberGenerator>(
        for item: Item,
        using generator: inout Generator
    ) -> ChoiceQuestion<Prompt, Answer> {
        let correct = answer(item)
        var distractors: [Answer] = []
        var seen: Set<Answer> = [correct]
        for candidate in distractorCandidates(for: item, using: &generator) {
            guard distractors.count < choiceCount - 1 else { break }
            let value = answer(candidate)
            if seen.insert(value).inserted {
                distractors.append(value)
            }
        }
        let choices = (distractors + [correct]).shuffled(using: &generator)
        return ChoiceQuestion(
            prompt: prompt(item),
            choices: choices,
            correctChoice: correct,
            scoreFactor: scoreFactor(item)
        )
    }

    /// 誤答の候補の並び。グループの指定があれば同じグループを先に、それ以外を後ろに並べる
    private func distractorCandidates<Generator: RandomNumberGenerator>(
        for item: Item,
        using generator: inout Generator
    ) -> [Item] {
        let shuffled = items.shuffled(using: &generator)
        guard let distractorGroup else { return shuffled }
        let group = distractorGroup(item)
        let sameGroup = shuffled.filter { distractorGroup($0) == group }
        let otherGroups = shuffled.filter { distractorGroup($0) != group }
        return sameGroup + otherGroups
    }

    /// 直近に出した問題を除いた行。すべて除くと空になるときは除外をあきらめる
    private func freshIndices() -> [Int] {
        let recent = Set(recentPrompts)
        let fresh = items.indices.filter { !recent.contains(prompt(items[$0])) }
        return fresh.isEmpty ? Array(items.indices) : fresh
    }

    private mutating func remember(_ value: Prompt) {
        guard recentWindow > 0 else { return }
        recentPrompts.append(value)
        if recentPrompts.count > recentWindow {
            recentPrompts.removeFirst(recentPrompts.count - recentWindow)
        }
    }
}

extension ChoiceQuestionGenerator {
    /// キーパスで列を指定する版
    public init(
        items: [Item],
        choiceCount: Int,
        prompt: KeyPath<Item, Prompt> & Sendable,
        answer: KeyPath<Item, Answer> & Sendable,
        recentWindow: Int = 5
    ) {
        self.init(
            items: items,
            choiceCount: choiceCount,
            prompt: { $0[keyPath: prompt] },
            answer: { $0[keyPath: answer] },
            recentWindow: recentWindow
        )
    }
}
