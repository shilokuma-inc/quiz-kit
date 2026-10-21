import Foundation

/// 1 問分の問題
///
/// 選択肢の型（`Choice`）はアプリが決める。2 択の「素数 / 素数でない」のような固定の選択肢でも、
/// 国旗クイズの「国名 4 つ」のように問題ごとに変わる選択肢でもよい。
/// 答えが合っているかは `isCorrect(_:)` だけで判定し、`QuizSession` は問題の中身を知らない。
public protocol QuizQuestion: Sendable {
    associatedtype Choice: Hashable & Sendable

    /// 画面に並べる選択肢（この順に並べる）
    var choices: [Choice] { get }

    /// `choice` を選んだら正解か
    func isCorrect(_ choice: Choice) -> Bool

    /// スコアの難易度係数。正解点は `基礎点 × scoreFactor` になる（既定は 1.0）
    var scoreFactor: Double { get }
}

extension QuizQuestion {
    public var scoreFactor: Double { 1.0 }
}

/// 問題文と選択肢を持つ、ふつうの択一問題
///
/// `Prompt` は問題として見せるもの（国旗の画像名・都道府県の形など）、`Choice` は選択肢。
/// データセットから作るときは `ChoiceQuestionGenerator` を使う。
public struct ChoiceQuestion<Prompt: Hashable & Sendable, Choice: Hashable & Sendable>: QuizQuestion, Hashable {
    public let prompt: Prompt
    public let choices: [Choice]
    public let correctChoice: Choice
    public let scoreFactor: Double

    public init(prompt: Prompt, choices: [Choice], correctChoice: Choice, scoreFactor: Double = 1.0) {
        precondition(choices.contains(correctChoice), "選択肢に正解が含まれていない")
        self.prompt = prompt
        self.choices = choices
        self.correctChoice = correctChoice
        self.scoreFactor = scoreFactor
    }

    public func isCorrect(_ choice: Choice) -> Bool {
        choice == correctChoice
    }
}
